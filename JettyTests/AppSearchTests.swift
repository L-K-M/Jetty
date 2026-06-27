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

    func testNextIndexWraps() {
        XCTAssertEqual(AppSearch.nextIndex(current: 2, delta: 1, count: 3), 0)
        XCTAssertEqual(AppSearch.nextIndex(current: 0, delta: -1, count: 3), 2)
        XCTAssertEqual(AppSearch.nextIndex(current: 0, delta: 1, count: 0), 0)
    }
}
