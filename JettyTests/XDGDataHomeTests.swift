import XCTest
@testable import Jetty

/// `$XDG_DATA_HOME` handling for `DockStore.defaultURL`'s Linux fallback. Runs on both
/// platforms — the rule is pure string logic, and testing it only where it is used
/// would leave it untested on the platform CI actually gates hardest.
final class XDGDataHomeTests: XCTestCase {

    private let home = "/home/tester"

    func testAbsoluteValueIsHonoured() {
        XCTAssertEqual(DockStore.xdgDataHome("/custom/data", home: home).path, "/custom/data")
    }

    func testUnsetFallsBackToTheDefault() {
        XCTAssertEqual(DockStore.xdgDataHome(nil, home: home).path, "/home/tester/.local/share")
    }

    /// The spec treats empty as unset, and a relative path as invalid rather than
    /// something to resolve against the working directory — which is how a dock file
    /// would otherwise land wherever the process happened to be started.
    func testEmptyAndRelativeValuesAreIgnored() {
        XCTAssertEqual(DockStore.xdgDataHome("", home: home).path, "/home/tester/.local/share")
        XCTAssertEqual(DockStore.xdgDataHome("relative/data", home: home).path,
                       "/home/tester/.local/share")
        // `~` is the tempting one to "fix" later: `getenv` hands back the literal
        // character — only a shell expands it — so a tilde value is non-absolute and
        // therefore invalid, like any other.
        XCTAssertEqual(DockStore.xdgDataHome("~/data", home: home).path,
                       "/home/tester/.local/share")
    }
}
