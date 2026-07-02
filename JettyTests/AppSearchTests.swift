import XCTest
import Foundation
@testable import Jetty

final class AppSearchTests: XCTestCase {

    private func item(_ name: String) -> AppSearchItem {
        AppSearchItem(name: name, bundleID: nil, url: URL(fileURLWithPath: "/Applications/\(name).app"))
    }

    func testSubsequenceMatches() {
        XCTAssertNotNil(AppSearch.score("term", "Terminal"))
        XCTAssertNotNil(AppSearch.score("Term", "Terminal"))   // case-insensitive
        XCTAssertNotNil(AppSearch.score("tl", "Terminal"))     // non-contiguous subsequence
    }

    func testNonSubsequenceDoesNotMatch() {
        XCTAssertNil(AppSearch.score("xyz", "Terminal"))
        XCTAssertNil(AppSearch.score("terminalx", "Terminal"))  // longer than candidate
    }

    func testPrefixBeatsMidwordSubsequence() {
        let results = AppSearch.rank("ter", in: [item("Master"), item("Terminal")])
        XCTAssertEqual(results.first?.name, "Terminal")
    }

    func testExactMatchScoresHighest() {
        let exact = AppSearch.score("Notes", "Notes")!
        let prefix = AppSearch.score("Note", "Notes")!
        XCTAssertGreaterThan(exact, prefix)
    }

    func testEmptyQueryReturnsAllSortedByName() {
        let results = AppSearch.rank("", in: [item("Safari"), item("Calendar"), item("Books")])
        XCTAssertEqual(results.map(\.name), ["Books", "Calendar", "Safari"])
    }

    /// Regression: a longer query that is still a prefix must keep matching, and apps
    /// that can't subsequence-match it must be excluded. Mirrors the user report that
    /// "IntelliJ" survived "intel" but vanished at "intell" while unrelated apps showed
    /// — proving the ranking itself is correct (the live bug was query staleness, not
    /// scoring). "WeChat" has no 'i' and "System Settings" has no 'l', so neither can
    /// match "intell"/"intelli".
    func testLongerPrefixQueryStillMatchesAndExcludesNonMatches() {
        for query in ["intel", "intell", "intelli"] {
            XCTAssertNotNil(AppSearch.score(query, "IntelliJ IDEA"), "‘\(query)’ should match IntelliJ")
            XCTAssertNil(AppSearch.score(query, "WeChat"), "‘\(query)’ must not match WeChat")
            XCTAssertNil(AppSearch.score(query, "System Settings"), "‘\(query)’ must not match System Settings")

            let ranked = AppSearch.rank(query, in: [item("WeChat"), item("System Settings"), item("IntelliJ IDEA")])
            XCTAssertEqual(ranked.map(\.name), ["IntelliJ IDEA"], "‘\(query)’ should rank only IntelliJ")
        }
    }

    func testDiacriticAndWidthInsensitive() {
        // ASCII query matches accented / full-width names (H4).
        XCTAssertNotNil(AppSearch.score("cafe", "Café"))
        XCTAssertNotNil(AppSearch.score("resume", "Résumé"))
        XCTAssertNotNil(AppSearch.score("n", "ñ"))
        XCTAssertEqual(AppSearch.score("Café", "Café"), AppSearch.score("cafe", "Café"))
        // Accented query still finds the accented name.
        XCTAssertNotNil(AppSearch.score("café", "Café"))
    }

    func testNextIndexWraps() {
        XCTAssertEqual(AppSearch.nextIndex(current: 2, delta: 1, count: 3), 0)
        XCTAssertEqual(AppSearch.nextIndex(current: 0, delta: -1, count: 3), 2)
        XCTAssertEqual(AppSearch.nextIndex(current: 0, delta: 1, count: 0), 0)
    }
}
