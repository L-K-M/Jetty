import XCTest
import Foundation
@testable import Jetty

final class RecentsTests: XCTestCase {

    private func entry(_ name: String, _ bundle: String?) -> RecentAppsStore.Entry {
        RecentAppsStore.Entry(name: name, bundleID: bundle, path: "/Applications/\(name).app")
    }

    func testUpdatedFrontInsertsAndDedupsByBundle() {
        var list = [entry("Safari", "com.apple.Safari"), entry("Mail", "com.apple.mail")]
        list = RecentAppsStore.updated(list, with: entry("Mail", "com.apple.mail"), cap: 8)
        XCTAssertEqual(list.map(\.name), ["Mail", "Safari"])   // Mail moved to front, not duplicated
    }

    func testUpdatedCaps() {
        var list: [RecentAppsStore.Entry] = []
        for i in 0..<12 { list = RecentAppsStore.updated(list, with: entry("App\(i)", "id\(i)"), cap: 8) }
        XCTAssertEqual(list.count, 8)
        XCTAssertEqual(list.first?.name, "App11")   // most recent first
    }

    private func item(_ name: String, _ bundle: String?) -> AppSearchItem {
        AppSearchItem(name: name, bundleID: bundle, url: URL(fileURLWithPath: "/Applications/\(name).app"))
    }

    func testEmptyQueryShowsRecentsFirst() {
        let apps = [item("Calendar", "c"), item("Safari", "s"), item("Mail", "m")]
        let recents = [item("Mail", "m")]
        let result = JettyMenuModel.rankedResults(query: "", apps: apps, recents: recents)
        XCTAssertEqual(result.first?.name, "Mail")           // recents lead
        XCTAssertEqual(result.filter { $0.name == "Mail" }.count, 1)  // not duplicated
        XCTAssertEqual(Set(result.map(\.name)), ["Mail", "Calendar", "Safari"])
    }

    func testNonEmptyQueryIgnoresRecents() {
        let apps = [item("Calendar", "c"), item("Safari", "s")]
        let result = JettyMenuModel.rankedResults(query: "saf", apps: apps, recents: [item("Calendar", "c")])
        XCTAssertEqual(result.first?.name, "Safari")
    }
}
