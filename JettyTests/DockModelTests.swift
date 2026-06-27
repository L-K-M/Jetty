import XCTest
@testable import Jetty

@MainActor
final class DockModelTests: XCTestCase {

    private func finderItem() -> DockItem {
        DockItem(kind: .application, displayName: "Finder", bundleIdentifier: "com.apple.finder")
    }

    func testRunningAppMergesIntoPinnedTile() {
        let pinned = [finderItem()]
        let running = [RunningAppInfo(bundleIdentifier: "com.apple.finder", name: "Finder", isActive: true, pid: 1)]
        let tiles = DockModel.makeTiles(pinned: pinned, running: running, showRunningApps: true)
        XCTAssertEqual(tiles.count, 1)
        XCTAssertTrue(tiles[0].isRunning)
        XCTAssertTrue(tiles[0].isActive)
        XCTAssertEqual(tiles[0].id, "app:com.apple.finder")
    }

    func testRunningOnlyAppsAppendedWhenEnabled() {
        let pinned = [finderItem()]
        let running = [
            RunningAppInfo(bundleIdentifier: "com.apple.finder", name: "Finder", isActive: false, pid: 1),
            RunningAppInfo(bundleIdentifier: "com.apple.Safari", name: "Safari", isActive: true, pid: 2),
        ]
        let tiles = DockModel.makeTiles(pinned: pinned, running: running, showRunningApps: true)
        XCTAssertEqual(tiles.map(\.id), ["app:com.apple.finder", "app:com.apple.Safari"])
        XCTAssertNil(tiles[1].itemID)   // running-only, not pinned
    }

    func testRunningOnlyAppsHiddenWhenDisabled() {
        let pinned = [finderItem()]
        let running = [RunningAppInfo(bundleIdentifier: "com.apple.Safari", name: "Safari", isActive: true, pid: 2)]
        let tiles = DockModel.makeTiles(pinned: pinned, running: running, showRunningApps: false)
        XCTAssertEqual(tiles.count, 1)
        XCTAssertEqual(tiles[0].id, "app:com.apple.finder")
    }

    func testNonAppItemsPassThroughInOrder() {
        let sep = DockItem(kind: .separator)
        let trash = DockItem(kind: .trash, displayName: "Trash")
        let tiles = DockModel.makeTiles(pinned: [finderItem(), sep, trash], running: [], showRunningApps: true)
        XCTAssertEqual(tiles.map(\.kind), [.application, .separator, .trash])
        XCTAssertEqual(tiles[1].id, "item:\(sep.id.uuidString)")
    }

    func testPinnedCountCountsOnlyPinnedTiles() {
        let model = DockModel()
        model.rebuild(pinned: [finderItem(), DockItem(kind: .separator)],
                      running: [RunningAppInfo(bundleIdentifier: "com.apple.Safari", name: "Safari", isActive: true, pid: 2)],
                      showRunningApps: true)
        XCTAssertEqual(model.tiles.count, 3)   // finder + separator + safari (running-only)
        XCTAssertEqual(model.pinnedCount, 2)   // only finder + separator are reorderable
    }

    func testPinnedAppNotDuplicatedByRunningList() {
        let pinned = [finderItem()]
        let running = [RunningAppInfo(bundleIdentifier: "com.apple.finder", name: "Finder", isActive: true, pid: 1)]
        let tiles = DockModel.makeTiles(pinned: pinned, running: running, showRunningApps: true)
        XCTAssertEqual(tiles.filter { $0.bundleIdentifier == "com.apple.finder" }.count, 1)
    }
}
