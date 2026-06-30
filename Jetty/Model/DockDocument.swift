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
    /// Displays the user has explicitly opted out of (no dock there), keyed by display
    /// UUID. Honored only while at least one *other* targeted display remains — Jetty
    /// never leaves every screen dockless (see `DockController.targetUUIDs`).
    var disabledDisplayUUIDs: Set<String>

    static let currentVersion = 1

    init(version: Int = DockDocument.currentVersion,
         items: [DockItem] = [],
         anchorsByDisplayUUID: [String: DockAnchor] = [:],
         disabledDisplayUUIDs: Set<String> = []) {
        self.version = version
        self.items = items
        self.anchorsByDisplayUUID = anchorsByDisplayUUID
        self.disabledDisplayUUIDs = disabledDisplayUUIDs
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? DockDocument.currentVersion
        // Lossy decoding (ISSUE-8): a single item/anchor with an unknown future enum
        // raw value (e.g. a `kind` from a newer build, or a hand-edited file) is
        // dropped instead of failing the whole document — so Jetty never silently
        // "loses the dock" and falls back to defaults over one bad entry.
        let rawItems = try c.decodeIfPresent([Failable<DockItem>].self, forKey: .items) ?? []
        items = rawItems.compactMap(\.value)
        let rawAnchors = try c.decodeIfPresent([String: Failable<DockAnchor>].self, forKey: .anchorsByDisplayUUID) ?? [:]
        anchorsByDisplayUUID = rawAnchors.compactMapValues(\.value)
        disabledDisplayUUIDs = try c.decodeIfPresent(Set<String>.self, forKey: .disabledDisplayUUIDs) ?? []
    }

    private enum CodingKeys: String, CodingKey {
        case version, items, anchorsByDisplayUUID, disabledDisplayUUIDs
    }
}

/// Decodes `T` if possible, else `nil` — never throws, so it can be used inside an
/// array/dictionary decode to skip undecodable elements (ISSUE-8).
private struct Failable<T: Decodable>: Decodable {
    let value: T?
    init(from decoder: Decoder) throws { value = try? T(from: decoder) }
}
