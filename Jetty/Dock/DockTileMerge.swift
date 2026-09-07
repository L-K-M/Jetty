import Foundation

/// The pure merge of pinned items and running apps into the dock's reorderable
/// slots. Lifted off `DockModel` in JP-06 so it can be exercised without AppKit,
/// Combine or a windowing stack; `DockModel` forwards to it and keeps the icon
/// resolution, which is the part that genuinely needs a colour/image framework.
///
/// Everything here is a function of its arguments, which is what makes the dock's
/// trickiest invariant (unique tile ids) testable at all. That claim is only true
/// because the one impure thing the merge needs — deciding whether a pinned folder
/// *is* the Trash — is injected. `TrashLocations.isTrashURL` reaches the filesystem
/// (`mountedVolumeURLs`, `fileExists`, `resolvingSymlinksInPath`) and the environment,
/// so it stays the default argument rather than a hidden call: production keeps the
/// real behaviour, and a test that cares about the merge can hand over a constant.
enum DockTileMerge {

    /// Merges pinned items (in authored order) with running apps into reorderable
    /// slots. A pinned app that is running is shown once (marked running). The
    /// running-but-not-pinned apps collapse into a single slot at the `.runningApps`
    /// sentinel's position (or, if no sentinel is present, appended at the end as a
    /// non-reorderable group). Icons are left nil.
    ///
    /// `isTrashURL` decides whether a pinned folder normalises to the Trash tile. It
    /// defaults to the real, filesystem-backed check; pass a constant to keep a test
    /// independent of the machine it runs on.
    static func makeSlots(pinned: [DockItem], running: [RunningAppInfo], showRunningApps: Bool,
                          isTrashURL: (URL) -> Bool = TrashLocations.isTrashURL) -> [DockSlot] {
        let runningByBundle: [String: RunningAppInfo] = Dictionary(
            running.compactMap { info in info.bundleIdentifier.map { ($0, info) } },
            // Two infos can share a bundle id (a relaunch race, or a second copy of the
            // same app). Only one instance can be frontmost, so prefer whichever is —
            // keeping the first would leave the pinned tile's active dot off while the
            // app has focus. Neither active: keep the first, as before.
            uniquingKeysWith: { a, b in a.isActive ? a : (b.isActive ? b : a) })
        let pinnedAppBundleIDs = Set(pinned.compactMap { $0.kind == .application ? $0.bundleIdentifier : nil })

        // Guard the invariant the rendering relies on: **unique tile ids**. Duplicate
        // ids (e.g. two running infos sharing a bundle id) would break id-keyed
        // magnification — the trailing icon stops zooming. Keep the first of any id.
        var seenRunningIDs = Set<String>()
        let runningOnly: [DockTile] = running.compactMap { info in
            if let b = info.bundleIdentifier, pinnedAppBundleIDs.contains(b) { return nil }
            // Same rule as `runningByBundle` above, which this deliberately reuses: on a
            // relaunch race the first info can be the inactive one, and keeping it would
            // leave an *unpinned* app's tile without its active dot while the app has
            // focus — the pinned path's bug, one code path over.
            let resolved = info.bundleIdentifier.flatMap { runningByBundle[$0] } ?? info
            // Dedup on the id the tile is *minted from*, not the raw one. They are equal
            // only while `RunningAppInfo.id` stays bundle-derived, which is a fact about
            // another file: were it ever pid-derived, two infos sharing a bundle would
            // both pass a raw-id check and both resolve to the same winner, minting two
            // tiles with one id — the desync this guard exists to prevent.
            guard seenRunningIDs.insert(resolved.id).inserted else { return nil }
            return DockTile(id: "app:\(resolved.id)", kind: .application, displayName: resolved.name,
                            bundleIdentifier: resolved.bundleIdentifier, url: nil, itemID: nil,
                            isRunning: true, isActive: resolved.isActive, pid: resolved.pid,
                            customIconPath: nil, folderDisplay: nil)
        }

        var slots: [DockSlot] = []
        var seenSlotIDs = Set<String>()
        // `slot:<uuid>` repeats for a repeated item id exactly as the tile id does.
        func uniqueSlotID(for item: DockItem) -> String {
            var id = "slot:\(item.id.uuidString)"
            var attempt = 1
            while !seenSlotIDs.insert(id).inserted {
                attempt += 1
                id = "slot:\(item.id.uuidString)#\(attempt)"
            }
            return id
        }
        var emittedRunning = false
        // The unique-tile-id invariant must hold across pinned items too, not just the
        // running-only list above: a second pin of the same app would otherwise reuse
        // `app:<bundleID>` and desync id-keyed magnification / hover / glow. Seed with the
        // running tile ids so a pin can't collide with a running-only tile either (F-M1).
        var seenTileIDs = Set(runningOnly.map(\.id))
        // The default check enumerates mounted volumes and resolves symlinks, so it is
        // not free and the dock rebuilds on every launch/activation. Memoised per merge
        // pass — one pass sees one filesystem, and the window is a single rebuild. This
        // wraps whatever was injected rather than replacing it.
        var trashAnswers: [URL: Bool] = [:]
        func checkTrash(_ url: URL) -> Bool {
            if let known = trashAnswers[url] { return known }
            let answer = isTrashURL(url)
            trashAnswers[url] = answer
            return answer
        }

        for item in pinned {
            if item.kind == .runningApps {
                // Emit the running-apps group at most once — a stray second `.runningApps`
                // sentinel must not re-emit the whole group (duplicating every tile id).
                if showRunningApps, !emittedRunning, !runningOnly.isEmpty {
                    slots.append(DockSlot(id: uniqueSlotID(for: item), itemID: item.id,
                                          tiles: runningOnly, isRunningGroup: true))
                }
                emittedRunning = true
                continue
            }
            // `dedupKey` is `app:<bundleID>` for apps (so a pin merges with its running
            // instance) else `item:<uuid>`. On a collision, fall back to the always-unique
            // item id so a duplicate pin can't break rendering (F-M1).
            var tileID = item.dedupKey
            if !seenTileIDs.insert(tileID).inserted {
                // `item:<uuid>` is only unique while item ids are, and nothing upstream
                // enforces that — a hand-edited or corrupted document can repeat one,
                // and for a non-application item `dedupKey` *is* `item:<uuid>`, so the
                // fallback would reproduce the very id that just collided.
                tileID = "item:\(item.id.uuidString)"
                var attempt = 1
                while !seenTileIDs.insert(tileID).inserted {
                    attempt += 1
                    tileID = "item:\(item.id.uuidString)#\(attempt)"
                }
            }
            let isTrash = item.kind == .trash || item.url.map(checkTrash) == true
            let info = isTrash ? nil : item.bundleIdentifier.flatMap { runningByBundle[$0] }
            let kind: DockItemKind = isTrash ? .trash : item.kind
            let displayName = isTrash ? (item.displayName.isEmpty ? "Trash" : item.displayName) : item.displayName
            let customIconPath = (!isTrash && item.kind.supportsCustomIcon)
                ? item.customIconPath : nil
            let tile = DockTile(id: tileID, kind: kind, displayName: displayName,
                                 bundleIdentifier: isTrash ? nil : item.bundleIdentifier,
                                 url: isTrash ? nil : item.url, itemID: item.id,
                                  isRunning: info != nil, isActive: info?.isActive ?? false, pid: info?.pid,
                                 customIconPath: customIconPath,
                                 // Complete the normalisation: `url`, `bundleIdentifier`
                                 // and `customIconPath` are already dropped, and a
                                 // folder-presentation style on a Trash tile is data an
                                 // authored `.trash` item would never carry. Not a live
                                 // bug — both readers of `folderDisplay` are guarded on
                                 // `kind == .folder` — but the asymmetry is what invites
                                 // one later.
                                 folderDisplay: isTrash ? nil : item.folderDisplay)
            slots.append(DockSlot(id: uniqueSlotID(for: item), itemID: item.id,
                                  tiles: [tile], isRunningGroup: false))
        }

        if showRunningApps && !emittedRunning && !runningOnly.isEmpty {
            slots.append(DockSlot(id: "running", itemID: nil, tiles: runningOnly, isRunningGroup: true))
        }
        return slots
    }

    /// Flat tiles in render order (derived from `makeSlots`). Kept for unit tests.
    static func makeTiles(pinned: [DockItem], running: [RunningAppInfo], showRunningApps: Bool,
                         isTrashURL: (URL) -> Bool = TrashLocations.isTrashURL) -> [DockTile] {
        makeSlots(pinned: pinned, running: running, showRunningApps: showRunningApps,
                  isTrashURL: isTrashURL).flatMap { $0.tiles }
    }
}
