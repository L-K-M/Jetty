import Foundation

/// Resolves a `DockItem`'s persisted bookmark (or plain URL fallback) to a live
/// `URL`, refreshing stale bookmarks. Keeping targets as bookmarks lets pinned
/// files/apps survive being moved or renamed. See PLAN.md §6.
enum BookmarkResolver {

    /// Creates bookmark `Data` for `url` (non-security-scoped; Jetty isn't sandboxed
    /// in v1, so plain bookmarks suffice — the App-Store path would switch to
    /// `.withSecurityScope`).
    static func bookmark(for url: URL) -> Data? {
        try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
    }

    /// Resolves an item to a current URL. Prefers the bookmark (tracks moves), and
    /// falls back to the stored `url`. `isStale` is reported so the caller can refresh.
    static func resolve(_ item: DockItem) -> (url: URL, isStale: Bool)? {
        if let data = item.bookmark {
            var stale = false
            if let url = try? URL(resolvingBookmarkData: data, options: [], relativeTo: nil, bookmarkDataIsStale: &stale) {
                return (url, stale)
            }
        }
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
