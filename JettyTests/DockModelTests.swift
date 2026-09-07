import XCTest
import AppKit
@testable import Jetty

@MainActor
final class DockModelTests: XCTestCase {

    private func finderItem() -> DockItem {
        DockItem(kind: .application, displayName: "Finder", bundleIdentifier: "com.apple.finder")
    }

    func testPinnedCountCountsOnlyPinnedTiles() {
        let model = DockModel()
        model.rebuild(pinned: [finderItem(), DockItem(kind: .separator)],
                      running: [RunningAppInfo(bundleIdentifier: "com.apple.Safari", name: "Safari", isActive: true, pid: 2)],
                      showRunningApps: true)
        XCTAssertEqual(model.tiles.count, 3)   // finder + separator + safari (running-only)
        XCTAssertEqual(model.pinnedCount, 2)   // only finder + separator are reorderable
    }

    func testDisabledDisplaysAreDroppedButNeverAll() {
        let a = "uuid-A", b = "uuid-B"
        // One of two displays disabled → only the other hosts a dock.
        XCTAssertEqual(DockController.enabledTargets(base: [a, b], disabled: [b]), [a])
        // The sole remaining display is the disabled one → it still gets a dock (never
        // left without one).
        XCTAssertEqual(DockController.enabledTargets(base: [b], disabled: [b]), [b])
        // Every display disabled → all fall back on, rather than zero docks.
        XCTAssertEqual(Set(DockController.enabledTargets(base: [a, b], disabled: [a, b])), Set([a, b]))
        // None disabled → unchanged.
        XCTAssertEqual(DockController.enabledTargets(base: [a, b], disabled: []), [a, b])
    }

    func testTrashEmptinessCountsHiddenItems() throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("JettyTrashTest-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        XCTAssertTrue(DockModel.isTrashEmpty(at: [folder]))

        try Data().write(to: folder.appendingPathComponent(".DS_Store"))
        try Data().write(to: folder.appendingPathComponent(".localized"))
        try Data().write(to: folder.appendingPathComponent("._.DS_Store"))
        try Data().write(to: folder.appendingPathComponent("._.localized"))
        XCTAssertTrue(DockModel.isTrashEmpty(at: [folder]))

        try Data().write(to: folder.appendingPathComponent(".hidden-file"))
        XCTAssertFalse(DockModel.isTrashEmpty(at: [folder]))
    }

    func testTrashTileAlwaysHasAnIcon() {
        // Whatever the resolved state, the tile must render a real trash can
        // (CoreTypes artwork, or the SF Symbol fallback) — never nil, never a
        // generic folder (TRASH.md).
        let model = DockModel()
        for state in [DockModel.TrashState.empty, .full, .unknown] {
            model.setTrashState(state)
            model.rebuild(pinned: [DockItem(kind: .trash, displayName: "Trash")],
                          running: [], showRunningApps: false)
            let tile = model.tiles.first { $0.kind == .trash }
            XCTAssertNotNil(tile?.icon, "state \(state)")
        }
    }

    func testTrashResolverPlan() {
        // A definitive probe always wins (Full Disk Access present).
        XCTAssertEqual(TrashStateResolver.plan(probe: .full, finderAutomationGranted: false),
                       .useProbe(.full))
        XCTAssertEqual(TrashStateResolver.plan(probe: .empty, finderAutomationGranted: true),
                       .useProbe(.empty))
        // A denied probe escalates to Finder only when Automation is consented —
        // never a passive consent prompt.
        XCTAssertEqual(TrashStateResolver.plan(probe: .unknown, finderAutomationGranted: true),
                       .askFinder)
        XCTAssertEqual(TrashStateResolver.plan(probe: .unknown, finderAutomationGranted: false),
                       .indeterminate)
    }
}
