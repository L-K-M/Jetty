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

    /// Folding must be locale-neutral (FAB-B11): a locale-aware fold under a
    /// Turkish/Azerbaijani locale maps "I" to dotless "ı", so "IINA" would never
    /// match the query "iina". A unit test can't safely flip the process locale,
    /// so assert the fold output directly — with `locale: nil` it must be "iina"
    /// regardless of the machine's locale — plus the end-to-end match.
    func testFoldingIsLocaleNeutral() {
        XCTAssertEqual(AppSearch.fold("IINA"), "iina")
        XCTAssertEqual(AppSearch.fold("I"), "i")
        XCTAssertNotNil(AppSearch.score("iina", "IINA"))
        XCTAssertEqual(AppSearch.rank("iina", in: [item("Terminal"), item("IINA")]).map(\.name),
                       ["IINA"])
    }

    /// Multi-word queries are word-order-insensitive (F-L5): the query is tokenized
    /// on whitespace and every token must match ("studio visual" used to match as
    /// the single ordered subsequence "studio visual", finding nothing).
    func testMultiWordQueryIsWordOrderInsensitive() {
        let items = [item("Visual Studio Code"), item("Xcode"), item("Safari")]
        XCTAssertEqual(AppSearch.rank("studio visual", in: items).map(\.name), ["Visual Studio Code"])
        XCTAssertEqual(AppSearch.rank("visual studio", in: items).map(\.name), ["Visual Studio Code"])
        XCTAssertEqual(AppSearch.rank("code visual", in: items).map(\.name), ["Visual Studio Code"])
    }

    /// Every token of a multi-word query must match (AND) — one miss excludes the item.
    func testMultiWordQueryRequiresEveryToken() {
        let items = [item("Visual Studio Code"), item("Xcode")]
        XCTAssertTrue(AppSearch.rank("visual zzz", in: items).isEmpty)
        XCTAssertTrue(AppSearch.rank("zzz studio", in: items).isEmpty)
    }

    /// Single-word ranking must be unchanged by the tokenization: a one-token query
    /// ranks exactly as `score` on the whole query does.
    func testSingleWordRankMatchesScore() {
        let items = [item("Master"), item("Terminal"), item("Notes")]
        let ranked = AppSearch.rank("ter", in: items)
        XCTAssertEqual(ranked.map(\.name), ["Terminal", "Master"])
        XCTAssertEqual(AppSearch.rank("notes", in: items).first?.name, "Notes")
    }

    func testNextIndexWraps() {
        XCTAssertEqual(AppSearch.nextIndex(current: 2, delta: 1, count: 3), 0)
        XCTAssertEqual(AppSearch.nextIndex(current: 0, delta: -1, count: 3), 2)
        XCTAssertEqual(AppSearch.nextIndex(current: 0, delta: 1, count: 0), 0)
    }
}
