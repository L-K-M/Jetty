import AppKit
import Combine
import Darwin

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
    /// Process id for a running-only tile, so a bundle-less app can still be activated
    /// by PID when there's no bundle id or app URL (ISSUE-1).
    var pid: pid_t?
    /// A user-chosen icon override path, carried from the backing item (MF-7).
    var customIconPath: String?
    /// For `.folder` tiles, how the stack popover presents its contents (MF-2).
    var folderDisplay: FolderStackStyle?
    /// Resolved lazily by `DockModel`; the pure `makeSlots`/`makeTiles` leave it nil.
    var icon: NSImage?

    /// Icon-cache key: the tile id plus the custom-icon path, so changing (or
    /// clearing) a custom icon doesn't return the stale cached image (MF-7 / BUG-8).
    var iconCacheKey: String { customIconPath.map { "\(id)|\($0)" } ?? id }
}

/// The observable tile/slot list the dock view renders, rebuilt whenever the pinned
/// items or the running-app set changes. The merge (`makeSlots`) is a **pure**
/// function over value types, so it's unit-tested without AppKit; icon resolution is
/// a separate, cached step. See PLAN.md §6–7.
final class DockModel: ObservableObject {

    enum TrashState {
        case empty
        case full
        case unknown
    }

    private enum TrashDirectoryState: String {
        case missing
        case empty
        case full
        case unreadable
    }

    /// Reorderable units (running apps collapse into one slot). The view renders these.
    @Published private(set) var slots: [DockSlot] = []
    /// Flat tiles in render order — used for deterministic panel sizing.
    @Published private(set) var tiles: [DockTile] = []

    private var iconCache = LRUImageCacheByKey(capacity: 256, maxAge: 5 * 60)

    // Interaction callbacks, wired by the DockController.
    var onOpenTile: ((DockTile) -> Void)?
    var onDropFiles: ((DockTile, [URL]) -> Void)?
    /// Builds the synthesized right-click menu for a tile (see PLAN.md §7).
    var onRequestContextActions: ((DockTile) -> [DockContextAction])?
    /// Drag-to-reorder: the new order of the reorderable slots' backing item ids.
    var onReorder: ((_ orderedItemIDs: [UUID]) -> Void)?
    /// Drag-out-to-remove: the backing item id of a tile dragged off the dock (ND-5).
    var onDragOutRemove: ((_ itemID: UUID) -> Void)?
    /// File/folder URLs dropped on the dock strip background (not a specific tile) —
    /// pin them as new items.
    var onAddDroppedItems: (([URL]) -> Void)?
    /// Hover entered/left a tile that shows a preview on hover — a running app (window
    /// peek) or a folder (contents stack). Drives the matching popover.
    var onHoverTile: ((DockTile, Bool) -> Void)?

    /// Count of pinned tiles (those with a backing item). Pinned tiles precede
    /// running-only ones in `tiles`. Kept for tests / sizing.
    var pinnedCount: Int { tiles.filter { $0.itemID != nil }.count }

    /// The item ids of the reorderable slots, in render order.
    var reorderableItemIDs: [UUID] { slots.compactMap { $0.itemID } }

    /// Rebuilds `slots`/`tiles` from the current pinned items + running apps and
    /// resolves icons (cached, bounded — BUG-8).
    func rebuild(pinned: [DockItem], running: [RunningAppInfo], showRunningApps: Bool) {
        let now = Date().timeIntervalSinceReferenceDate
        let built = Self.makeSlots(pinned: pinned, running: running, showRunningApps: showRunningApps)
        let trashState = built.flatMap(\.tiles).contains { $0.kind == .trash }
            ? Self.trashState() : nil
        slots = built.map { slot in
            DockSlot(id: slot.id, itemID: slot.itemID,
                      tiles: slot.tiles.map { tile in
                          var t = tile
                          if t.kind == .trash {
                              t.icon = Self.trashIcon(state: trashState ?? .empty)
                          } else {
                              t.icon = icon(for: tile, now: now)
                          }
                          return t
                      },
                     isRunningGroup: slot.isRunningGroup)
        }
        tiles = slots.flatMap { $0.tiles }
    }

    /// Kept as the controller's "Trash changed" hook; Trash state is intentionally
    /// re-read on every rebuild so a missed filesystem event can't leave a stale can.
    func invalidateTrashIcon() {}

    // MARK: Pure merge (unit-tested)

    /// Merges pinned items (in authored order) with running apps into reorderable
    /// slots. A pinned app that is running is shown once (marked running). The
    /// running-but-not-pinned apps collapse into a single slot at the `.runningApps`
    /// sentinel's position (or, if no sentinel is present, appended at the end as a
    /// non-reorderable group). Icons are left nil.
    static func makeSlots(pinned: [DockItem], running: [RunningAppInfo], showRunningApps: Bool) -> [DockSlot] {
        let runningByBundle: [String: RunningAppInfo] = Dictionary(
            running.compactMap { info in info.bundleIdentifier.map { ($0, info) } },
            uniquingKeysWith: { a, _ in a })
        let pinnedAppBundleIDs = Set(pinned.compactMap { $0.kind == .application ? $0.bundleIdentifier : nil })

        // Guard the invariant the rendering relies on: **unique tile ids**. Duplicate
        // ids (e.g. two running infos sharing a bundle id) would break id-keyed
        // magnification — the trailing icon stops zooming. Keep the first of any id.
        var seenRunningIDs = Set<String>()
        let runningOnly: [DockTile] = running.compactMap { info in
            if let b = info.bundleIdentifier, pinnedAppBundleIDs.contains(b) { return nil }
            guard seenRunningIDs.insert(info.id).inserted else { return nil }
            return DockTile(id: "app:\(info.id)", kind: .application, displayName: info.name,
                            bundleIdentifier: info.bundleIdentifier, url: nil, itemID: nil,
                            isRunning: true, isActive: info.isActive, pid: info.pid,
                            customIconPath: nil, folderDisplay: nil, icon: nil)
        }

        var slots: [DockSlot] = []
        var emittedRunning = false
        // The unique-tile-id invariant must hold across pinned items too, not just the
        // running-only list above: a second pin of the same app would otherwise reuse
        // `app:<bundleID>` and desync id-keyed magnification / hover / glow. Seed with the
        // running tile ids so a pin can't collide with a running-only tile either (F-M1).
        var seenTileIDs = Set(runningOnly.map(\.id))

        for item in pinned {
            if item.kind == .runningApps {
                // Emit the running-apps group at most once — a stray second `.runningApps`
                // sentinel must not re-emit the whole group (duplicating every tile id).
                if showRunningApps, !emittedRunning, !runningOnly.isEmpty {
                    slots.append(DockSlot(id: "slot:\(item.id.uuidString)", itemID: item.id,
                                          tiles: runningOnly, isRunningGroup: true))
                }
                emittedRunning = true
                continue
            }
            // `dedupKey` is `app:<bundleID>` for apps (so a pin merges with its running
            // instance) else `item:<uuid>`. On a collision, fall back to the always-unique
            // item id so a duplicate pin can't break rendering (F-M1).
            var tileID = item.dedupKey
            if !seenTileIDs.insert(tileID).inserted {
                tileID = "item:\(item.id.uuidString)"
                seenTileIDs.insert(tileID)
            }
            let isTrash = item.kind == .trash || item.url.map(TrashLocations.isTrashURL) == true
            let info = isTrash ? nil : item.bundleIdentifier.flatMap { runningByBundle[$0] }
            let kind: DockItemKind = isTrash ? .trash : item.kind
            let displayName = isTrash ? (item.displayName.isEmpty ? "Trash" : item.displayName) : item.displayName
            let customIconPath = isTrash ? nil : item.customIconPath
            let tile = DockTile(id: tileID, kind: kind, displayName: displayName,
                                 bundleIdentifier: isTrash ? nil : item.bundleIdentifier,
                                 url: isTrash ? nil : item.url, itemID: item.id,
                                 isRunning: info != nil, isActive: info?.isActive ?? false, pid: nil,
                                 customIconPath: customIconPath, folderDisplay: item.folderDisplay, icon: nil)
            slots.append(DockSlot(id: "slot:\(item.id.uuidString)", itemID: item.id,
                                  tiles: [tile], isRunningGroup: false))
        }

        if showRunningApps && !emittedRunning && !runningOnly.isEmpty {
            slots.append(DockSlot(id: "running", itemID: nil, tiles: runningOnly, isRunningGroup: true))
        }
        return slots
    }

    /// Flat tiles in render order (derived from `makeSlots`). Kept for unit tests.
    static func makeTiles(pinned: [DockItem], running: [RunningAppInfo], showRunningApps: Bool) -> [DockTile] {
        makeSlots(pinned: pinned, running: running, showRunningApps: showRunningApps).flatMap { $0.tiles }
    }

    // MARK: Icons (bounded LRU — BUG-8)

    private func icon(for tile: DockTile, now: TimeInterval) -> NSImage? {
        if tile.kind == .trash {
            // Handled in `rebuild`, which computes the empty/full state once and then
            // selects the native empty/full Trash image.
            return nil
        }
        let cacheKey = tile.iconCacheKey
        if let cached = iconCache.value(for: cacheKey, now: now) { return cached }
        // A user-chosen icon overrides the default for any kind (MF-7).
        if let path = tile.customIconPath, let custom = NSImage(contentsOfFile: path) {
            iconCache.insert(custom, for: cacheKey, now: now)
            return custom
        }
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
            image = nil
        case .separator, .clock, .jettyMenu, .runningApps,
             .battery, .systemMonitor, .worldClock, .pomodoro, .weather, .nowPlaying:
            image = nil   // rendered with custom views
        }
        if let image { iconCache.insert(image, for: cacheKey, now: now) }
        return image
    }

    private func appURL(forBundleID bundleID: String?) -> URL? {
        guard let bundleID else { return nil }
        return NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
    }

    /// The system Trash icon reflecting empty vs. full (IDEA-5). A live `DockController`
    /// trash watcher triggers a rebuild so this re-evaluates when the Trash changes.
    static func trashIcon() -> NSImage? {
        trashIcon(state: trashState())
    }

    static func trashIcon(isEmpty: Bool) -> NSImage? {
        trashIcon(state: isEmpty ? .empty : .full)
    }

    private static func trashIcon(state: TrashState) -> NSImage? {
        NSImage(named: trashImageName(for: state))
    }

    static func trashImageName(for state: TrashState) -> NSImage.Name {
        // Full must mean that a real entry was positively observed. Mounted and cloud
        // volumes can expose protected `.Trashes` paths that Jetty cannot inspect even
        // while Finder reports an empty Trash; one unrelated permission failure must
        // not make the can permanently full.
        switch state {
        case .full: return NSImage.trashFullName
        case .empty, .unknown: return NSImage.trashEmptyName
        }
    }

    /// Whether the user's Trash is empty. Missing candidate folders are empty; any
    /// readable candidate containing a real entry makes the Trash full.
    static func isTrashEmpty() -> Bool {
        trashState() != .full
    }

    static func isTrashEmpty(at trashURLs: [URL]) -> Bool {
        trashState(at: trashURLs) != .full
    }

    private static func trashState() -> TrashState {
        trashState(at: TrashLocations.candidateTrashURLs())
    }

    private static func trashState(at trashURLs: [URL]) -> TrashState {
        var sawUnreadable = false
        for trash in trashURLs {
            switch trashDirectoryState(trash) {
            case .full: return .full
            case .unreadable: sawUnreadable = true
            case .empty, .missing: break
            }
        }
        return sawUnreadable ? .unknown : .empty
    }

    private static func trashDirectoryState(_ trash: URL) -> TrashDirectoryState {
        // `contentsOfDirectory` materializes every name. Trash only needs to know
        // whether one real entry exists, so stop at the first via `readdir` instead.
        guard let dir = opendir(trash.path) else {
            switch errno {
            case ENOENT, ENOTDIR: return .missing
            default: return .unreadable
            }
        }
        defer { closedir(dir) }

        errno = 0
        while let entry = readdir(dir) {
            var dName = entry.pointee.d_name
            let capacity = MemoryLayout.size(ofValue: dName)
            let name = withUnsafePointer(to: &dName) { pointer in
                pointer.withMemoryRebound(to: CChar.self, capacity: capacity) {
                    String(cString: $0)
                }
            }
            if isRealTrashEntry(name) { return .full }
        }
        return errno == 0 ? .empty : .unreadable
    }

    private static func isRealTrashEntry(_ name: String) -> Bool {
        switch name {
        case ".", "..", ".DS_Store", ".localized", "._.DS_Store", "._.localized":
            return false
        default:
            return true
        }
    }
}
