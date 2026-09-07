#if canImport(AppKit)
import AppKit
#endif
import Foundation

/// One rendered dock tile: the merge of a pinned item and/or a running app.
///
/// A pure value type, so `DockTileMerge` can build a whole dock without a windowing
/// stack. Every field here is data the merge decides; the only exception is `icon`,
/// which is resolved later by `DockModel` at render time and is therefore Darwin-only
/// for now — see the note on that property.
struct DockTile: Identifiable {
    let id: String
    var kind: DockItemKind
    var displayName: String
    var bundleIdentifier: String?
    var url: URL?
    /// The backing pinned item, if this tile came from one (nil for running-only).
    var itemID: UUID?
    var isRunning: Bool
    var isActive: Bool
    /// Process id for a running-only tile, so a bundle-less app can still be activated
    /// by PID when there's no bundle id or app URL (ISSUE-1).
    var pid: pid_t?
    /// A user-chosen icon override path, carried from the backing item (MF-7).
    var customIconPath: String?
    /// For `.folder` tiles, how the stack popover presents its contents (MF-2).
    var folderDisplay: FolderStackStyle?

    #if canImport(AppKit)
    /// Resolved lazily by `DockModel`; the pure merge leaves it nil.
    ///
    /// Darwin-only, and deliberately *not* a portable image handle. The port plan
    /// called for "PictKit's neutral handle", but PictKit is a macOS package (AppKit,
    /// ImageIO, CoreServices, min macOS 13) and is not a dependency of the SwiftPM
    /// target at all, so there is nothing neutral to point at. Nor is one needed yet:
    /// the merge only ever leaves this nil, every reader (`DockTileView`,
    /// `TileAccent`, `DockView`) is already Darwin-only, and off Darwin there is no
    /// renderer to hand an image to. The default below is what lets the portable
    /// merge construct a tile without naming the field.
    var icon: NSImage? = nil
    #endif

    /// Icon-cache key: the tile id plus the custom-icon path, so changing (or
    /// clearing) a custom icon doesn't return the stale cached image (MF-7 / BUG-8).
    var iconCacheKey: String { customIconPath.map { "\(id)|\($0)" } ?? id }
}
