import AppKit
import Combine

/// One rendered dock tile: the merge of a pinned item and/or a running app.
struct DockTile: Identifiable {
    let id: String
    var kind: DockItemKind
    var displayName: String
    var bundleIdentifier: String?
    var url: URL?
    /// The backing pinned item, if this tile came from one (nil for running-only).
    var itemID: UUID?
    var isRunning: Bool
    var isActive: Bool
    /// Process id for a running-only tile, so a bundle-less app can still be activated
    /// by PID when there's no bundle id or app URL (ISSUE-1).
    var pid: pid_t?
    /// A user-chosen icon override path, carried from the backing item (MF-7).
    var customIconPath: String?
    /// For `.folder` tiles, how the stack popover presents its contents (MF-2).
    var folderDisplay: FolderStackStyle?
    /// Resolved lazily by `DockModel`; the pure `makeSlots`/`makeTiles` leave it nil.
    var icon: NSImage?

    /// Icon-cache key: the tile id plus the custom-icon path, so changing (or
    /// clearing) a custom icon doesn't return the stale cached image (MF-7 / BUG-8).
    var iconCacheKey: String { customIconPath.map { "\(id)|\($0)" } ?? id }
}

/// The observable tile/slot list the dock view renders, rebuilt whenever the pinned
/// items or the running-app set changes. The merge (`makeSlots`) is a **pure**
/// function over value types, so it's unit-tested without AppKit; icon resolution is
/// a separate, cached step. See PLAN.md §6–7.
final class DockModel: ObservableObject {

    /// Reorderable units (running apps collapse into one slot). The view renders these.
    @Published private(set) var slots: [DockSlot] = []
    /// Flat tiles in render order — used for deterministic panel sizing.
    @Published private(set) var tiles: [DockTile] = []

    private var iconCache = LRUImageCacheByKey(capacity: 256, maxAge: 5 * 60)
    /// The Trash icon (empty/full) is recomputed only when the Trash actually changes
    /// (via `invalidateTrashIcon()` from the controller's `TrashMonitor`), not on every
    /// rebuild — a rebuild fires on each app focus change (IDEA-5 / ISSUE-5 spirit).
    private var trashIconCache: NSImage?

    // Interaction callbacks, wired by the DockController.
    var onOpenTile: ((DockTile) -> Void)?
    var onDropFiles: ((DockTile, [URL]) -> Void)?
    /// Builds the synthesized right-click menu for a tile (see PLAN.md §7).
    var onRequestContextActions: ((DockTile) -> [DockContextAction])?
    /// Drag-to-reorder: the new order of the reorderable slots' backing item ids.
    var onReorder: ((_ orderedItemIDs: [UUID]) -> Void)?
    /// Drag-out-to-remove: the backing item id of a tile dragged off the dock (ND-5).
    var onDragOutRemove: ((_ itemID: UUID) -> Void)?
    /// File/folder URLs dropped on the dock strip background (not a specific tile) —
    /// pin them as new items.
    var onAddDroppedItems: (([URL]) -> Void)?
    /// Hover entered/left a running application tile — drives the window-peek popover.
    var onHoverApp: ((DockTile, Bool) -> Void)?

    /// Count of pinned tiles (those with a backing item). Pinned tiles precede
    /// running-only ones in `tiles`. Kept for tests / sizing.
    var pinnedCount: Int { tiles.filter { $0.itemID != nil }.count }

    /// The item ids of the reorderable slots, in render order.
    var reorderableItemIDs: [UUID] { slots.compactMap { $0.itemID } }

    /// Rebuilds `slots`/`tiles` from the current pinned items + running apps and
    /// resolves icons (cached, bounded — BUG-8).
    func rebuild(pinned: [DockItem], running: [RunningAppInfo], showRunningApps: Bool) {
        let now = Date().timeIntervalSinceReferenceDate
        let built = Self.makeSlots(pinned: pinned, running: running, showRunningApps: showRunningApps)
        slots = built.map { slot in
            DockSlot(id: slot.id, itemID: slot.itemID,
                     tiles: slot.tiles.map { tile in
                         var t = tile
                         t.icon = icon(for: tile, now: now)
                         return t
                     },
                     isRunningGroup: slot.isRunningGroup)
        }
        tiles = slots.flatMap { $0.tiles }
    }

    /// Drops the cached Trash icon so the next rebuild re-reads empty/full (IDEA-5).
    func invalidateTrashIcon() { trashIconCache = nil }

    // MARK: Pure merge (unit-tested)

    /// Merges pinned items (in authored order) with running apps into reorderable
    /// slots. A pinned app that is running is shown once (marked running). The
    /// running-but-not-pinned apps collapse into a single slot at the `.runningApps`
    /// sentinel's position (or, if no sentinel is present, appended at the end as a
    /// non-reorderable group). Icons are left nil.
    static func makeSlots(pinned: [DockItem], running: [RunningAppInfo], showRunningApps: Bool) -> [DockSlot] {
        let runningByBundle: [String: RunningAppInfo] = Dictionary(
            running.compactMap { info in info.bundleIdentifier.map { ($0, info) } },
            uniquingKeysWith: { a, _ in a })
        let pinnedAppBundleIDs = Set(pinned.compactMap { $0.kind == .application ? $0.bundleIdentifier : nil })

        // Guard the invariant the rendering relies on: **unique tile ids**. Duplicate
        // ids (e.g. two running infos sharing a bundle id) would break id-keyed
        // magnification — the trailing icon stops zooming. Keep the first of any id.
        var seenRunningIDs = Set<String>()
        let runningOnly: [DockTile] = running.compactMap { info in
            if let b = info.bundleIdentifier, pinnedAppBundleIDs.contains(b) { return nil }
            guard seenRunningIDs.insert(info.id).inserted else { return nil }
            return DockTile(id: "app:\(info.id)", kind: .application, displayName: info.name,
                            bundleIdentifier: info.bundleIdentifier, url: nil, itemID: nil,
                            isRunning: true, isActive: info.isActive, pid: info.pid,
                            customIconPath: nil, folderDisplay: nil, icon: nil)
        }

        var slots: [DockSlot] = []
        var emittedRunning = false

        for item in pinned {
            if item.kind == .runningApps {
                guard showRunningApps else { emittedRunning = true; continue }
                if !runningOnly.isEmpty {
                    slots.append(DockSlot(id: "slot:\(item.id.uuidString)", itemID: item.id,
                                          tiles: runningOnly, isRunningGroup: true))
                }
                emittedRunning = true
                continue
            }
            let tileID: String
            if item.kind == .application, let bundleID = item.bundleIdentifier {
                tileID = "app:\(bundleID)"
            } else {
                tileID = "item:\(item.id.uuidString)"
            }
            let info = item.bundleIdentifier.flatMap { runningByBundle[$0] }
            let tile = DockTile(id: tileID, kind: item.kind, displayName: item.displayName,
                                bundleIdentifier: item.bundleIdentifier, url: item.url, itemID: item.id,
                                isRunning: info != nil, isActive: info?.isActive ?? false, pid: nil,
                                customIconPath: item.customIconPath, folderDisplay: item.folderDisplay, icon: nil)
            slots.append(DockSlot(id: "slot:\(item.id.uuidString)", itemID: item.id,
                                  tiles: [tile], isRunningGroup: false))
        }

        if showRunningApps && !emittedRunning && !runningOnly.isEmpty {
            slots.append(DockSlot(id: "running", itemID: nil, tiles: runningOnly, isRunningGroup: true))
        }
        return slots
    }

    /// Flat tiles in render order (derived from `makeSlots`). Kept for unit tests.
    static func makeTiles(pinned: [DockItem], running: [RunningAppInfo], showRunningApps: Bool) -> [DockTile] {
        makeSlots(pinned: pinned, running: running, showRunningApps: showRunningApps).flatMap { $0.tiles }
    }

    // MARK: Icons (bounded LRU — BUG-8)

    private func icon(for tile: DockTile, now: TimeInterval) -> NSImage? {
        // The Trash reflects empty/full state (IDEA-5). Cached separately and refreshed
        // only when the Trash changes (see `invalidateTrashIcon()`), so a moved/quit app
        // rebuild doesn't re-list the Trash directory.
        if tile.kind == .trash, tile.customIconPath == nil {
            if let cached = trashIconCache { return cached }
            let image = Self.trashIcon()
            trashIconCache = image
            return image
        }
        let cacheKey = tile.iconCacheKey
        if let cached = iconCache.value(for: cacheKey, now: now) { return cached }
        // A user-chosen icon overrides the default for any kind (MF-7).
        if let path = tile.customIconPath, let custom = NSImage(contentsOfFile: path) {
            iconCache.insert(custom, for: cacheKey, now: now)
            return custom
        }
        var image: NSImage?
        switch tile.kind {
        case .application, .file, .folder, .url:
            if let url = tile.url ?? appURL(forBundleID: tile.bundleIdentifier) {
                image = NSWorkspace.shared.icon(forFile: url.path)
            } else if let bundleID = tile.bundleIdentifier,
                      let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
                image = NSWorkspace.shared.icon(forFile: url.path)
            }
        case .trash:
            image = Self.trashIcon()
        case .separator, .clock, .jettyMenu, .runningApps,
             .battery, .systemMonitor, .worldClock, .pomodoro, .weather, .nowPlaying:
            image = nil   // rendered with custom views
        }
        if let image { iconCache.insert(image, for: cacheKey, now: now) }
        return image
    }

    private func appURL(forBundleID bundleID: String?) -> URL? {
        guard let bundleID else { return nil }
        return NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
    }

    /// The system Trash icon reflecting empty vs. full (IDEA-5). A live `DockController`
    /// trash watcher triggers a rebuild so this re-evaluates when the Trash changes.
    static func trashIcon() -> NSImage? {
        let trash = (try? FileManager.default.url(for: .trashDirectory, in: .userDomainMask,
                                                  appropriateFor: nil, create: false))
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".Trash")
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: trash, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
        let name = contents.isEmpty ? NSImage.trashEmptyName : NSImage.trashFullName
        return NSImage(named: name)
    }
}
