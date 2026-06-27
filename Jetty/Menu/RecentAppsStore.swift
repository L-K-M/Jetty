import Foundation

/// Tracks the apps Jetty has recently launched/activated, most-recent-first, for the
/// Jetty Menu's recents section (MF-5). Permission-free: it only records launches
/// Jetty itself triggers, persisted as small JSON in `UserDefaults`.
final class RecentAppsStore {

    static let shared = RecentAppsStore()

    struct Entry: Codable, Equatable {
        var name: String
        var bundleID: String?
        var path: String
    }

    private let defaults: UserDefaults
    private let key = "JettyMenu.recentApps"
    let cap = 8

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    private(set) var entries: [Entry] {
        get {
            guard let data = defaults.data(forKey: key) else { return [] }
            return (try? JSONDecoder().decode([Entry].self, from: data)) ?? []
        }
        set { defaults.set(try? JSONEncoder().encode(newValue), forKey: key) }
    }

    /// Records a launch/activation, moving it to the front and de-duplicating.
    func record(name: String, bundleID: String?, url: URL) {
        entries = Self.updated(entries, with: Entry(name: name, bundleID: bundleID, path: url.path), cap: cap)
    }

    /// Recent apps resolved to `AppSearchItem`s, skipping any that no longer exist.
    func recentItems() -> [AppSearchItem] {
        entries.compactMap { entry in
            guard FileManager.default.fileExists(atPath: entry.path) else { return nil }
            return AppSearchItem(name: entry.name, bundleID: entry.bundleID,
                                 url: URL(fileURLWithPath: entry.path))
        }
    }

    /// Pure list update (front-insert, dedup by bundle id or path, cap) — unit-tested.
    static func updated(_ list: [Entry], with entry: Entry, cap: Int) -> [Entry] {
        var result = list.filter { existing in
            if let b = entry.bundleID, existing.bundleID == b { return false }
            return existing.path != entry.path
        }
        result.insert(entry, at: 0)
        if result.count > cap { result = Array(result.prefix(cap)) }
        return result
    }
}
