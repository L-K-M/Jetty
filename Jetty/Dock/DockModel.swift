import AppKit
import Combine

/// One rendered dock tile: the merge of a pinned item and/or a running app.
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
    /// Resolved lazily by `DockModel`; the pure `makeTiles` leaves it nil.
    var icon: NSImage?
}

/// The observable tile list the dock view renders, rebuilt whenever the pinned
/// items or the running-app set changes. The merge itself
/// (`makeTiles`) is a **pure** function over value types, so it's unit-tested
/// without AppKit; icon resolution is a separate, cached step. See PLAN.md §6–7.
final class DockModel: ObservableObject {

    @Published private(set) var tiles: [DockTile] = []

    private var iconCache: [String: NSImage] = [:]

    // Interaction callbacks, wired by the DockController.
    var onOpenTile: ((DockTile) -> Void)?
    var onDropFiles: ((DockTile, [URL]) -> Void)?
    /// Builds the synthesized right-click menu for a tile (see PLAN.md §7).
    var onRequestContextActions: ((DockTile) -> [DockContextAction])?

    /// Rebuilds `tiles` from the current pinned items + running apps and resolves
    /// icons (cached).
    func rebuild(pinned: [DockItem], running: [RunningAppInfo], showRunningApps: Bool) {
        var built = Self.makeTiles(pinned: pinned, running: running, showRunningApps: showRunningApps)
        for i in built.indices {
            built[i].icon = icon(for: built[i])
        }
        tiles = built
    }

    // MARK: Pure merge (unit-tested)

    /// Merges pinned items (in their authored order) with running apps. A running app
    /// already pinned (matched by bundle id) is shown once, marked running; remaining
    /// running apps are appended when `showRunningApps` is on. Icons are left nil.
    static func makeTiles(pinned: [DockItem], running: [RunningAppInfo], showRunningApps: Bool) -> [DockTile] {
        let runningByBundle: [String: RunningAppInfo] = Dictionary(
            running.compactMap { info in info.bundleIdentifier.map { ($0, info) } },
            uniquingKeysWith: { a, _ in a })

        var seen = Set<String>()
        var tiles: [DockTile] = []

        for item in pinned {
            let info = item.bundleIdentifier.flatMap { runningByBundle[$0] }
            let id: String
            if item.kind == .application, let bundleID = item.bundleIdentifier {
                id = "app:\(bundleID)"
                seen.insert(bundleID)
            } else {
                id = "item:\(item.id.uuidString)"
            }
            tiles.append(DockTile(id: id,
                                  kind: item.kind,
                                  displayName: item.displayName,
                                  bundleIdentifier: item.bundleIdentifier,
                                  url: item.url,
                                  itemID: item.id,
                                  isRunning: info != nil,
                                  isActive: info?.isActive ?? false,
                                  icon: nil))
        }

        if showRunningApps {
            for info in running {
                if let bundleID = info.bundleIdentifier {
                    if seen.contains(bundleID) { continue }
                    seen.insert(bundleID)
                }
                tiles.append(DockTile(id: "app:\(info.id)",
                                      kind: .application,
                                      displayName: info.name,
                                      bundleIdentifier: info.bundleIdentifier,
                                      url: nil,
                                      itemID: nil,
                                      isRunning: true,
                                      isActive: info.isActive,
                                      icon: nil))
            }
        }

        return tiles
    }

    // MARK: Icons

    private func icon(for tile: DockTile) -> NSImage? {
        if let cached = iconCache[tile.id] { return cached }
        var image: NSImage?
        switch tile.kind {
        case .application, .file, .folder, .url:
            if let url = tile.url ?? appURL(forBundleID: tile.bundleIdentifier) {
                image = NSWorkspace.shared.icon(forFile: url.path)
            } else if let bundleID = tile.bundleIdentifier,
                      let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
                image = NSWorkspace.shared.icon(forFile: url.path)
            }
        case .trash:
            let trash = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".Trash")
            image = NSWorkspace.shared.icon(forFile: trash.path)
        case .separator, .clock, .jettyMenu:
            image = nil   // rendered with custom views
        }
        if let image { iconCache[tile.id] = image }
        return image
    }

    private func appURL(forBundleID bundleID: String?) -> URL? {
        guard let bundleID else { return nil }
        return NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
    }
}
