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
}
