import XCTest
@testable import Jetty

/// The URL-fallback path — which on Linux is the whole of `BookmarkResolver`, because
/// bookmarks are a Darwin filesystem feature and a Linux `dock.json` therefore carries
/// only the absolute `url`. Worth pinning on both platforms rather than only where it
/// is the sole path: macOS takes the same route for any item stored without a
/// bookmark, and it was previously untested there too. See
/// `docs/linux-port-plan.md` §JP-04.
final class BookmarkResolverTests: XCTestCase {

    private let path = URL(fileURLWithPath: "/tmp/jetty-notes.txt")

    func testResolvesTheStoredURLWhenThereIsNoBookmark() {
        let item = DockItem(kind: .file, displayName: "Notes", url: path)
        let resolved = BookmarkResolver.resolve(item)
        XCTAssertEqual(resolved?.url, path)
        XCTAssertEqual(resolved?.isStale, false, "a plain URL is never stale — there is nothing to refresh")
    }

    func testResolvesToNilWithNeitherBookmarkNorURL() {
        XCTAssertNil(BookmarkResolver.resolve(DockItem(kind: .file, displayName: "Nothing")))
    }

    /// An unresolvable bookmark must not swallow the item: the stored URL is still the
    /// answer. This is the case a Linux build hits for every item written by a macOS
    /// build, since it carries bookmark bytes this platform cannot read.
    func testFallsBackToTheURLWhenTheBookmarkIsUnusable() {
        let item = DockItem(kind: .file, displayName: "Notes",
                            bookmark: Data([0xDE, 0xAD, 0xBE, 0xEF]), url: path)
        XCTAssertEqual(BookmarkResolver.resolve(item)?.url, path)
    }

    /// Refreshing a bookmarkless item is a no-op rather than a rewrite — which is what
    /// keeps a Linux store from rewriting `dock.json` on every resolve.
    func testRefreshedIfStaleLeavesABookmarklessItemAlone() {
        let item = DockItem(kind: .file, displayName: "Notes", url: path)
        XCTAssertEqual(BookmarkResolver.refreshedIfStale(item), item)
    }

    #if canImport(Darwin)
    /// The Darwin half, which this port gated behind `canImport(Darwin)` and which had
    /// no coverage on the only platform that runs it: a bookmark is created, and it
    /// **wins over** the stored `url`. Asserted by pointing the two at different files,
    /// so a `resolve` that quietly stopped preferring the bookmark would fail here
    /// rather than pass by coincidence.
    ///
    /// Deliberately not asserting that a bookmark tracks a *moved* file. That is real
    /// behaviour and the reason bookmarks are used at all, but it belongs to the OS
    /// rather than to this function, and a test for it could not be run from the Linux
    /// container this was written in. Precedence is the branch, and precedence is
    /// deterministic.
    func testResolvePrefersAValidBookmarkOverTheStoredURL() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let bookmarked = dir.appendingPathComponent("jetty-bookmarked-\(UUID().uuidString).txt")
        try "x".write(to: bookmarked, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: bookmarked) }

        let data = try XCTUnwrap(BookmarkResolver.bookmark(for: bookmarked),
                                 "bookmark(for:) must produce data on Darwin")
        let decoy = dir.appendingPathComponent("jetty-decoy-\(UUID().uuidString).txt")
        let item = DockItem(kind: .file, displayName: "Notes", bookmark: data, url: decoy)

        let resolved = try XCTUnwrap(BookmarkResolver.resolve(item))
        XCTAssertEqual(resolved.url.resolvingSymlinksInPath().path,
                       bookmarked.resolvingSymlinksInPath().path,
                       "the bookmark, not the stored url, decides")
    }
    #endif
}
