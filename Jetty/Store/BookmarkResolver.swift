import Foundation

/// Resolves a `DockItem`'s persisted bookmark (or plain URL fallback) to a live
/// `URL`, refreshing stale bookmarks. Keeping targets as bookmarks lets pinned
/// files/apps survive being moved or renamed. See PLAN.md §6.
enum BookmarkResolver {

    /// Creates bookmark `Data` for `url` (non-security-scoped; Jetty isn't sandboxed
    /// in v1, so plain bookmarks suffice — the App-Store path would switch to
    /// `.withSecurityScope`).
    ///
    /// Bookmarks are a Darwin filesystem feature: `URL.bookmarkData` does not exist in
    /// swift-corelibs-foundation, verified against the pinned toolchain. Returning nil
    /// elsewhere is not a stub — it is the same answer this function already gives for
    /// an unbookmarkable URL, and `resolve` already falls through to the stored
    /// absolute path, which is what a Linux `dock.json` carries.
    static func bookmark(for url: URL) -> Data? {
        #if canImport(Darwin)
        return try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
        #else
        return nil
        #endif
    }

    /// Resolves an item to a current URL. Prefers the bookmark (tracks moves), and
    /// falls back to the stored `url`. `isStale` is reported so the caller can refresh.
    static func resolve(_ item: DockItem) -> (url: URL, isStale: Bool)? {
        #if canImport(Darwin)
        if let data = item.bookmark {
            var stale = false
            if let url = try? URL(resolvingBookmarkData: data, options: [], relativeTo: nil, bookmarkDataIsStale: &stale) {
                return (url, stale)
            }
        }
        #endif
        if let url = item.url { return (url, false) }
        return nil
    }

    /// Returns a copy of `item` with a freshened bookmark if its current one is stale
    /// (and resolvable), else the item unchanged.
    static func refreshedIfStale(_ item: DockItem) -> DockItem {
        guard let (url, stale) = resolve(item), stale, let data = bookmark(for: url) else { return item }
        var copy = item
        copy.bookmark = data
        copy.url = url
        return copy
    }
}
