import Foundation

/// The persisted root: the ordered pinned items plus any per-display position
/// overrides. Written as JSON to Application Support; a `version` field drives
/// forward migrations. See PLAN.md §6, §11.
struct DockDocument: Codable, Equatable {
    var version: Int
    var items: [DockItem]
    /// Per-display placement overrides, keyed by display UUID. Displays without an
    /// entry fall back to the global default anchor in `Preferences`.
    var anchorsByDisplayUUID: [String: DockAnchor]

    static let currentVersion = 1

    init(version: Int = DockDocument.currentVersion,
         items: [DockItem] = [],
         anchorsByDisplayUUID: [String: DockAnchor] = [:]) {
        self.version = version
        self.items = items
        self.anchorsByDisplayUUID = anchorsByDisplayUUID
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? DockDocument.currentVersion
        items = try c.decodeIfPresent([DockItem].self, forKey: .items) ?? []
        anchorsByDisplayUUID = try c.decodeIfPresent([String: DockAnchor].self, forKey: .anchorsByDisplayUUID) ?? [:]
    }

    private enum CodingKeys: String, CodingKey { case version, items, anchorsByDisplayUUID }
}
