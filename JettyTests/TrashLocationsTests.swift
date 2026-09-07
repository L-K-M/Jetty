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
    /// The trash root honours `$XDG_DATA_HOME`, pinned against a **literal** rather than
    /// against the expression `userTrashURL()` is built from.
    ///
    /// The previous version compared `userTrashURL()` with
    /// `XDGPaths.dataHome().appendingPathComponent("Trash")` — which is its
    /// implementation, so it could not fail, and with the variable unset (the usual CI
    /// case) even a regression hardcoding `~/.local/share/Trash` stayed green. That is
    /// the second time on this PR I wrote the shape the test above rejects, once in the
    /// very commit that deleted the first one.
    ///
    /// `ProcessInfo.processInfo.environment` reads the environment live on
    /// swift-corelibs-foundation — measured on the pinned toolchain — so `setenv` here
    /// is observed by `XDGPaths.dataHome()`.
    func testUserTrashURLHonoursXDGDataHome() {
        // Save and *restore* rather than unset: the variable may legitimately be set in
        // the environment this runs in, and `unsetenv` in a defer would clobber it for
        // every test after this one instead of putting it back.
        let saved = ProcessInfo.processInfo.environment["XDG_DATA_HOME"]
        setenv("XDG_DATA_HOME", "/tmp/jetty-xdg-probe", 1)
        defer {
            if let saved { setenv("XDG_DATA_HOME", saved, 1) } else { unsetenv("XDG_DATA_HOME") }
        }
        XCTAssertEqual(TrashLocations.userTrashURL().path, "/tmp/jetty-xdg-probe/Trash")
        XCTAssertEqual(TrashLocations.trashContentsURLs().map(\.path),
                       ["/tmp/jetty-xdg-probe/Trash/files"])
    }
    #endif

    /// The shared XDG rule, pinned against the **spec** rather than against another
    /// implementation of it.
    ///
    /// This replaced an "agree with `DockStore.xdgDataHome`" assertion that could not
    /// fail: `DockStore` forwards here, so it compared the function with itself. That
    /// is the same vacuous shape rejected on #78 (a parity test between `NSColor(hex:)`
    /// and the `RGBA8(hex:)` it delegates to) — written here by the same hand that
    /// rejected it there, which is why it is spelled out.
    func testXDGDataHomeFollowsTheSpec() {
        // Absolute wins verbatim.
        XCTAssertEqual(XDGPaths.dataHome("/custom/data", home: "/home/u").path, "/custom/data")
        // Unset falls back to the documented default.
        XCTAssertEqual(XDGPaths.dataHome(nil, home: "/home/u").path, "/home/u/.local/share")
        // Empty is "unset", not a path — `URL(fileURLWithPath: "")` is the *cwd*.
        XCTAssertEqual(XDGPaths.dataHome("", home: "/home/u").path, "/home/u/.local/share")
        // Relative is invalid per the spec, and must not resolve against cwd or home.
        XCTAssertEqual(XDGPaths.dataHome("relative/path", home: "/home/u").path, "/home/u/.local/share")
    }
}
