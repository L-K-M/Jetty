import XCTest
@testable import Jetty

final class TrashLocationsTests: XCTestCase {

    /// Identity ("is this folder the Trash?") and contents ("what holds the discarded
    /// items?") are the same directory on Darwin and different ones under XDG, where
    /// the trash directory holds `files/` and `info/`. Probing the root would report
    /// "not empty" forever, since those two survive emptying.
    func testTrashContentsAreWhereItemsActuallyLive() {
        let contents = TrashLocations.trashContentsURLs()
        XCTAssertFalse(contents.isEmpty)
        #if canImport(Darwin)
        XCTAssertEqual(contents.map(\.path), TrashLocations.candidateTrashURLs().map(\.path))
        #else
        XCTAssertTrue(contents.allSatisfy { $0.lastPathComponent == "files" },
                      "XDG items live in Trash/files, not at the Trash root")
        // Shape alone would pass on *any* files/ directory; pin that the home trash's
        // own is actually among them, so dropping it can't ship green.
        XCTAssertTrue(contents.map(\.path)
                        .contains(TrashLocations.userTrashURL().appendingPathComponent("files").path),
                      "the home trash's files/ must be among the probed contents")
        XCTAssertFalse(contents.map(\.path).contains(TrashLocations.userTrashURL().path),
                       "the Trash root must not be probed for contents")
        #endif
    }

    #if !canImport(Darwin)
    /// The trash root follows `$XDG_DATA_HOME`, through the same shared rule the
    /// persisted document location uses.
    func testUserTrashURLFollowsTheSharedXDGRule() {
        XCTAssertEqual(TrashLocations.userTrashURL().path,
                       XDGPaths.dataHome().appendingPathComponent("Trash").path)
    }
    #endif

    /// One XDG rule, not two: `DockStore` and `TrashLocations` must agree, or the
    /// persisted document and the trash would disagree about `$XDG_DATA_HOME`.
    func testDockStoreAndXDGPathsAgree() {
        for value in ["/custom/data", "", "relative/path"] as [String?] + [nil] {
            XCTAssertEqual(DockStore.xdgDataHome(value, home: "/home/u").path,
                           XDGPaths.dataHome(value, home: "/home/u").path,
                           "diverged on \(String(describing: value))")
        }
    }
}
