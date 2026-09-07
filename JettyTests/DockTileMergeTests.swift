import XCTest
@testable import Jetty

/// The pure tile/slot merge, exercised without AppKit, Combine or a windowing stack.
/// Split out of `DockModelTests` in JP-06 together with `DockTileMerge` itself: these
/// assertions are unchanged, they simply now name the type that actually owns the
/// logic. The `DockModel`-instance, `DockController` and Trash-probing cases stayed
/// behind, because those genuinely need Darwin.
final class DockTileMergeTests: XCTestCase {

    private func finderItem() -> DockItem {
        DockItem(kind: .application, displayName: "Finder", bundleIdentifier: "com.apple.finder")
    }

    func testRunningAppMergesIntoPinnedTile() {
        let pinned = [finderItem()]
        let running = [RunningAppInfo(bundleIdentifier: "com.apple.finder", name: "Finder", isActive: true, pid: 1)]
        let tiles = DockTileMerge.makeTiles(pinned: pinned, running: running, showRunningApps: true)
        XCTAssertEqual(tiles.count, 1)
        XCTAssertTrue(tiles[0].isRunning)
        XCTAssertTrue(tiles[0].isActive)
        XCTAssertEqual(tiles[0].id, "app:com.apple.finder")
        XCTAssertEqual(tiles[0].pid, 1)
    }

    func testRunningOnlyAppsAppendedWhenEnabled() {
        let pinned = [finderItem()]
        let running = [
            RunningAppInfo(bundleIdentifier: "com.apple.finder", name: "Finder", isActive: false, pid: 1),
            RunningAppInfo(bundleIdentifier: "com.apple.Safari", name: "Safari", isActive: true, pid: 2),
        ]
        let tiles = DockTileMerge.makeTiles(pinned: pinned, running: running, showRunningApps: true)
        XCTAssertEqual(tiles.map(\.id), ["app:com.apple.finder", "app:com.apple.Safari"])
        XCTAssertNil(tiles[1].itemID)   // running-only, not pinned
    }

    func testDuplicateRunningAppsYieldUniqueTileIDs() {
        // Two running infos sharing a bundle id (relaunch/activation race, or a bundle
        // with a second regular process) must not mint two tiles with the same id —
        // that desyncs id-keyed magnification so a trailing icon stops zooming.
        let pinned = [finderItem()]
        let running = [
            RunningAppInfo(bundleIdentifier: "com.panic.Transmit", name: "Transmit", isActive: false, pid: 10),
            RunningAppInfo(bundleIdentifier: "com.panic.Transmit", name: "Transmit", isActive: true, pid: 11),
            RunningAppInfo(bundleIdentifier: "com.apple.Safari", name: "Safari", isActive: false, pid: 12),
        ]
        let tiles = DockTileMerge.makeTiles(pinned: pinned, running: running, showRunningApps: true)
        XCTAssertEqual(tiles.map(\.id), ["app:com.apple.finder", "app:com.panic.Transmit", "app:com.apple.Safari"])
        XCTAssertEqual(Set(tiles.map(\.id)).count, tiles.count)   // all ids unique
    }

    func testDuplicatePinnedAppYieldsUniqueTileIDs() {
        // Pinning the same app twice (or two on-disk copies) must not mint two tiles
        // with the same "app:<bundleID>" id — that desyncs id-keyed magnification /
        // hover / glow. The second falls back to its unique item id (F-M1).
        let a = finderItem()
        let b = DockItem(kind: .application, displayName: "Finder", bundleIdentifier: "com.apple.finder")
        let tiles = DockTileMerge.makeTiles(pinned: [a, b], running: [], showRunningApps: true)
        XCTAssertEqual(tiles.count, 2)
        XCTAssertEqual(Set(tiles.map(\.id)).count, 2)          // ids are unique
        XCTAssertEqual(tiles[0].id, "app:com.apple.finder")
        XCTAssertEqual(tiles[1].id, "item:\(b.id.uuidString)") // second falls back to item id
    }

    func testSecondRunningAppsSentinelDoesNotDuplicateGroup() {
        // A stray second .runningApps sentinel must not re-emit the whole running group
        // (which would duplicate every running tile id) (F-M1).
        let pinned = [
            finderItem(),
            DockItem(kind: .runningApps, displayName: "Running Apps"),
            DockItem(kind: .runningApps, displayName: "Running Apps"),
        ]
        let running = [RunningAppInfo(bundleIdentifier: "com.apple.Safari", name: "Safari", isActive: true, pid: 2)]
        let tiles = DockTileMerge.makeTiles(pinned: pinned, running: running, showRunningApps: true)
        XCTAssertEqual(tiles.map(\.id), ["app:com.apple.finder", "app:com.apple.Safari"])
        XCTAssertEqual(Set(tiles.map(\.id)).count, tiles.count)
    }

    func testRunningOnlyAppsHiddenWhenDisabled() {
        let pinned = [finderItem()]
        let running = [RunningAppInfo(bundleIdentifier: "com.apple.Safari", name: "Safari", isActive: true, pid: 2)]
        let tiles = DockTileMerge.makeTiles(pinned: pinned, running: running, showRunningApps: false)
        XCTAssertEqual(tiles.count, 1)
        XCTAssertEqual(tiles[0].id, "app:com.apple.finder")
    }

    func testNonAppItemsPassThroughInOrder() {
        let sep = DockItem(kind: .separator)
        let trash = DockItem(kind: .trash, displayName: "Trash")
        let tiles = DockTileMerge.makeTiles(pinned: [finderItem(), sep, trash], running: [], showRunningApps: true)
        XCTAssertEqual(tiles.map(\.kind), [.application, .separator, .trash])
        XCTAssertEqual(tiles[1].id, "item:\(sep.id.uuidString)")
    }

    func testUnsupportedKindsIgnorePersistedCustomIconPath() {
        let trash = DockItem(kind: .trash, displayName: "Trash", customIconPath: "/tmp/stale.icns")
        let clock = DockItem(kind: .clock, displayName: "Clock", customIconPath: "/tmp/clock.icns")
        let file = DockItem(kind: .file, displayName: "File", customIconPath: "/tmp/file.icns")

        let tiles = DockTileMerge.makeTiles(pinned: [trash, clock, file], running: [], showRunningApps: true)

        XCTAssertNil(tiles[0].customIconPath)
        XCTAssertNil(tiles[1].customIconPath)
        XCTAssertEqual(tiles[2].customIconPath, "/tmp/file.icns")
    }

    func testPinnedTrashFolderNormalizesToTrashTile() {
        let folder = DockItem(kind: .folder, displayName: "Trash", url: TrashLocations.userTrashURL(),
                              folderDisplay: .grid, customIconPath: "/tmp/stale.icns")

        let tile = DockTileMerge.makeTiles(pinned: [folder], running: [], showRunningApps: true)[0]

        XCTAssertEqual(tile.kind, .trash)
        XCTAssertNil(tile.url)
        XCTAssertNil(tile.customIconPath)
    }

    func testRunningAppsCollapseIntoOneSlotAtSentinel() {
        let pinned = [
            finderItem(),
            DockItem(kind: .runningApps, displayName: "Running Apps"),
            DockItem(kind: .clock, displayName: "Clock"),
        ]
        let running = [
            RunningAppInfo(bundleIdentifier: "com.apple.Safari", name: "Safari", isActive: true, pid: 2),
            RunningAppInfo(bundleIdentifier: "com.apple.mail", name: "Mail", isActive: false, pid: 3),
        ]
        let slots = DockTileMerge.makeSlots(pinned: pinned, running: running, showRunningApps: true)
        XCTAssertEqual(slots.count, 3)                      // finder | running group | clock
        XCTAssertTrue(slots[1].isRunningGroup)
        XCTAssertEqual(slots[1].tiles.count, 2)             // safari + mail as one slot
        XCTAssertNotNil(slots[1].itemID)                    // reorderable as a unit
        XCTAssertEqual(slots[2].tiles.first?.kind, .clock)  // clock sits AFTER running apps
    }

    /// The sentinel skip must hold for the tile walk as well as the slot walk, or a
    /// stray "Running Apps" tile could leak through `makeTiles` while `makeSlots` stays
    /// correct.
    func testDisabledSentinelLeaksNoTileThroughMakeTiles() {
        let pinned = [DockItem(kind: .application, displayName: "Finder",
                               bundleIdentifier: "com.apple.finder"),
                      DockItem(kind: .runningApps, displayName: "Running Apps")]
        let running = [RunningAppInfo(bundleIdentifier: "com.apple.Safari", name: "Safari",
                                      isActive: true, pid: 2)]
        XCTAssertEqual(DockTileMerge.makeTiles(pinned: pinned, running: running,
                                               showRunningApps: false,
                                               isTrashURL: { _ in false }).map(\.id),
                       ["app:com.apple.finder"])
    }

    func testRunningAppsSentinelSkippedWhenHidden() {
        let pinned = [finderItem(), DockItem(kind: .runningApps, displayName: "Running Apps")]
        let running = [RunningAppInfo(bundleIdentifier: "com.apple.Safari", name: "Safari", isActive: true, pid: 2)]
        let slots = DockTileMerge.makeSlots(pinned: pinned, running: running, showRunningApps: false)
        XCTAssertEqual(slots.count, 1)                      // only finder; no running group
        XCTAssertFalse(slots.contains { $0.isRunningGroup })
    }

    func testPinnedAppNotDuplicatedByRunningList() {
        let pinned = [finderItem()]
        let running = [RunningAppInfo(bundleIdentifier: "com.apple.finder", name: "Finder", isActive: true, pid: 1)]
        let tiles = DockTileMerge.makeTiles(pinned: pinned, running: running, showRunningApps: true)
        XCTAssertEqual(tiles.filter { $0.bundleIdentifier == "com.apple.finder" }.count, 1)
    }

    /// The Trash normalisation is the merge's one impure need, so it is injected. This
    /// pins the wiring and, unlike the default-argument case above, does not depend on
    /// the machine the test runs on.
    func testTrashNormalisationUsesTheInjectedCheck() {
        let folder = DockItem(kind: .folder, displayName: "Downloads",
                              url: URL(fileURLWithPath: "/tmp/not-the-trash"),
                              folderDisplay: .grid, customIconPath: "/tmp/icon.icns")

        let asFolder = DockTileMerge.makeTiles(pinned: [folder], running: [], showRunningApps: true,
                                               isTrashURL: { _ in false })[0]
        XCTAssertEqual(asFolder.kind, .folder)
        XCTAssertNotNil(asFolder.url)

        let asTrash = DockTileMerge.makeTiles(pinned: [folder], running: [], showRunningApps: true,
                                              isTrashURL: { _ in true })[0]
        XCTAssertEqual(asTrash.kind, .trash)
        XCTAssertNil(asTrash.url)
        XCTAssertNil(asTrash.customIconPath)
    }

    /// The fallback id is only unique while *item* ids are, and nothing upstream
    /// enforces that — a hand-edited or corrupted document can repeat one. For a
    /// non-application item `dedupKey` is already `item:<uuid>`, so the fallback used
    /// to reproduce the very id that had just collided, and the guard silently failed
    /// at its one job. Slot ids carried the same exposure.
    func testRepeatedItemIDStillYieldsUniqueTileAndSlotIDs() {
        let shared = UUID()
        let a = DockItem(id: shared, kind: .separator)
        let b = DockItem(id: shared, kind: .separator)
        let c = DockItem(id: shared, kind: .separator)

        let slots = DockTileMerge.makeSlots(pinned: [a, b, c], running: [], showRunningApps: true,
                                            isTrashURL: { _ in false })
        let tileIDs = slots.flatMap { $0.tiles }.map(\.id)
        let slotIDs = slots.map(\.id)

        XCTAssertEqual(tileIDs.count, 3)
        XCTAssertEqual(Set(tileIDs).count, 3, "duplicate tile ids desync id-keyed magnification (F-M1)")
        XCTAssertEqual(Set(slotIDs).count, 3, "ForEach over duplicate slot ids is undefined")
        XCTAssertEqual(tileIDs.first, "item:\(shared.uuidString)", "the first id must be unchanged")
    }

    /// Only one instance can be frontmost, so when two running infos share a bundle id
    /// the merge must not keep an inactive one and leave the tile's active dot off.
    func testDuplicateRunningInfosPreferTheActiveInstance() {
        let pinned = [DockItem(kind: .application, displayName: "Transmit",
                               bundleIdentifier: "com.panic.Transmit")]
        let running = [
            RunningAppInfo(bundleIdentifier: "com.panic.Transmit", name: "Transmit", isActive: false, pid: 10),
            RunningAppInfo(bundleIdentifier: "com.panic.Transmit", name: "Transmit", isActive: true, pid: 11),
        ]
        let tile = DockTileMerge.makeTiles(pinned: pinned, running: running, showRunningApps: true,
                                           isTrashURL: { _ in false })[0]
        XCTAssertTrue(tile.isActive)
        XCTAssertEqual(tile.pid, 11)
    }

    /// Neither instance active: first-wins, as before — the prefer-active rule must not
    /// quietly reorder the ordinary case.
    func testDuplicateRunningInfosKeepTheFirstWhenNeitherIsActive() {
        let pinned = [DockItem(kind: .application, displayName: "Transmit",
                               bundleIdentifier: "com.panic.Transmit")]
        let running = [
            RunningAppInfo(bundleIdentifier: "com.panic.Transmit", name: "Transmit", isActive: false, pid: 10),
            RunningAppInfo(bundleIdentifier: "com.panic.Transmit", name: "Transmit", isActive: false, pid: 11),
        ]
        let tile = DockTileMerge.makeTiles(pinned: pinned, running: running, showRunningApps: true,
                                           isTrashURL: { _ in false })[0]
        XCTAssertEqual(tile.pid, 10)
    }

    /// The memo must wrap the injected check, not replace it, and must not re-ask for a
    /// URL it has already answered.
    func testTrashCheckIsAskedOncePerDistinctURL() {
        var asked: [URL] = []
        let repeated = URL(fileURLWithPath: "/tmp/same-folder")
        let distinct = URL(fileURLWithPath: "/tmp/other-folder")
        let items = [repeated, repeated, repeated, distinct].map {
            DockItem(kind: .folder, displayName: "F", url: $0, folderDisplay: .grid)
        }
        _ = DockTileMerge.makeTiles(pinned: items, running: [], showRunningApps: true,
                                    isTrashURL: { asked.append($0); return false })
        // A second, distinct URL is what makes this test able to fail: asserting only a
        // count with one URL would also pass for a cache that answers *every* URL from
        // the first verdict, which would misclassify every later folder in the merge.
        XCTAssertEqual(asked, [repeated, distinct],
                       "each distinct URL must be probed exactly once; got \(asked)")
    }

    /// The active-instance rule has to hold for the running-apps *group* as well as for
    /// pinned tiles: an unpinned app in a relaunch race would otherwise show no active
    /// dot while it has focus.
    func testUnpinnedDuplicateRunningInfosPreferTheActiveInstance() {
        let running = [
            RunningAppInfo(bundleIdentifier: "com.panic.Transmit", name: "Transmit", isActive: false, pid: 10),
            RunningAppInfo(bundleIdentifier: "com.panic.Transmit", name: "Transmit", isActive: true, pid: 11),
        ]
        let tiles = DockTileMerge.makeTiles(pinned: [], running: running, showRunningApps: true,
                                            isTrashURL: { _ in false })
        XCTAssertEqual(tiles.count, 1)
        XCTAssertTrue(tiles[0].isActive)
        XCTAssertEqual(tiles[0].pid, 11)
        XCTAssertEqual(tiles[0].id, "app:com.panic.Transmit", "tile identity must not shift")
    }
}
