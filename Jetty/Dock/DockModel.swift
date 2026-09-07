import AppKit
import Combine
import Darwin
import PictKit

/// The observable tile/slot list the dock view renders, rebuilt whenever the pinned
/// items or the running-app set changes. The merge itself lives in the portable
/// `DockTileMerge` — a **pure** function over value types, unit-tested without
/// AppKit — and this class adds the part that genuinely needs a colour/image
/// framework: cached icon resolution. See PLAN.md §6–7.
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
    /// Best-effort Not Responding state, keyed by exact process identity. This changes
    /// tile overlays only; it must not rebuild or relayout the dock.
    @Published private(set) var unresponsivePIDs = Set<pid_t>()

    /// `DockModel.`, not `Self.`, and it has to stay that way: a stored property
    /// initializer runs before there is a `self`, so `Self` is the covariant dynamic
    /// type there and the compiler rejects it outright — "covariant 'Self' type
    /// cannot be referenced from a stored property initializer". `final` does not
    /// help. The `Self.` in `invalidateIcons()` below is fine because that one has a
    /// `self` to be relative to.
    private var iconCache = DockModel.makeIconCache()

    /// One definition of the cache's shape. It is built in two places — here and on
    /// invalidation — and two literals drift.
    private static func makeIconCache() -> LRUImageCacheByKey {
        LRUImageCacheByKey(capacity: 256, maxAge: 5 * 60)
    }

    init() {
        // An icon set in Pict (or Zap, or Top Drawer) has to reach the dock without
        // a relaunch. The 5-minute TTL would get there eventually, which is not the
        // same as arriving — so this drops the cache instead.
        //
        // Already on the main queue from either side that fires it: `IconStoreWatcher`
        // hops there before calling back (its `deliver()`), because FSEvents delivers
        // on its own utility queue, and `IconResolver.onIconsResolved` is documented
        // to arrive on main too. Wrapping this in `DispatchQueue.main.async` would
        // only delay the invalidation by a runloop turn.
        JettyIcons.shared.onIconsInvalidated = { [weak self] in
            self?.invalidateIcons()
        }
    }

    /// Drops every cached icon and redraws. Cheap: the tiles themselves are
    /// untouched, so this is a re-resolve rather than a rebuild.
    func invalidateIcons() {
        iconCache = Self.makeIconCache()
        objectWillChange.send()
    }

    // Interaction callbacks, wired by the DockController.
    var onOpenTile: ((DockTile) -> Void)?
    var onDropFiles: ((DockTile, [URL]) -> Void)?
    /// Builds the synthesized right-click menu for a tile (see PLAN.md §7).
    var onRequestContextActions: ((DockTile) -> [DockContextAction])?
    /// Holds auto-hide while a native context menu is tracking outside the dock panel.
    var onContextMenuPresentationChanged: ((String, Bool) -> Void)?
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

    func setUnresponsivePIDs(_ value: Set<pid_t>) {
        if value != unresponsivePIDs { unresponsivePIDs = value }
    }

    func isUnresponsive(pid: pid_t?) -> Bool {
        pid.map(unresponsivePIDs.contains) ?? false
    }

    /// The currently resolved Trash fullness, pushed by the controller's
    /// `TrashStateResolver` pipeline (probe → Finder Automation → honest default;
    /// see TRASH.md). `.unknown` renders the empty can by policy. Never probed
    /// synchronously in `rebuild` — that was the old main-thread beach-ball and the
    /// reason the can was stuck (TCC denies enumeration without Full Disk Access).
    private(set) var trashState: TrashState = .unknown

    /// Updates the resolved Trash state; the controller calls `rebuild` afterwards
    /// when it changed.
    func setTrashState(_ state: TrashState) { trashState = state }

    /// The user's chosen Trash tile style (`.default` = the system can), pushed by
    /// the controller from Preferences before each rebuild.
    private(set) var trashIconStyle: TrashIconStyle = .default

    /// Updates the Trash tile style; the controller calls `rebuild` afterwards.
    func setTrashIconStyle(_ style: TrashIconStyle) { trashIconStyle = style }

    /// Rebuilds `slots`/`tiles` from the current pinned items + running apps and
    /// resolves icons (cached, bounded — BUG-8).
    func rebuild(pinned: [DockItem], running: [RunningAppInfo], showRunningApps: Bool) {
        let now = Date().timeIntervalSinceReferenceDate
        let built = DockTileMerge.makeSlots(pinned: pinned, running: running, showRunningApps: showRunningApps)
        slots = built.map { slot in
            DockSlot(id: slot.id, itemID: slot.itemID,
                      tiles: slot.tiles.map { tile in
                          var t = tile
                          if t.kind == .trash {
                              // Policy: `.unknown` renders empty — the Trash is empty
                              // most of the time, and a false full cried wolf
                              // constantly in the old code (41d4b62).
                              t.icon = TrashIconProvider.icon(isFull: trashState == .full, style: trashIconStyle)
                          } else {
                              t.icon = icon(for: tile, now: now)
                          }
                          return t
                      },
                     isRunningGroup: slot.isRunningGroup)
        }
        tiles = slots.flatMap { $0.tiles }
    }

    // MARK: Icons (bounded LRU — BUG-8)

    private func icon(for tile: DockTile, now: TimeInterval) -> NSImage? {
        if tile.kind == .trash {
            // Handled by `rebuild` directly, from the resolved `trashState` via
            // `TrashIconProvider` (never probed synchronously here — see TRASH.md).
            return nil
        }
        let cacheKey = tile.iconCacheKey
        if let cached = iconCache.value(for: cacheKey, now: now) { return cached }
        // A user-chosen icon overrides the default for any kind (MF-7). This stays
        // the top rung: a per-item choice is more specific than a shared one and was
        // made more deliberately, and two tiles pointing at one app are allowed to
        // differ. So nobody's existing icons change when the shared store arrives.
        if let path = tile.customIconPath, let custom = NSImage(contentsOfFile: path) {
            iconCache.insert(custom, for: cacheKey, now: now)
            return custom
        }
        var image: NSImage?
        switch tile.kind {
        case .application, .file, .folder, .url:
            if let url = tile.url ?? appURL(forBundleID: tile.bundleIdentifier) {
                // Rungs 2 and 3, from PictKit: an icon the user set in Pict (or Zap,
                // or Top Drawer), then the bundle's own un-masked artwork. A miss
                // returns nil and warms in the background, so this stays a
                // dictionary lookup on a path that rebuilds the whole dock.
                image = JettyIcons.shared.icon(for: target(for: tile, url: url))
                    ?? NSWorkspace.shared.icon(forFile: url.path)
            } else if let bundleID = tile.bundleIdentifier,
                      let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
                image = JettyIcons.shared.icon(for: target(for: tile, url: url))
                    ?? NSWorkspace.shared.icon(forFile: url.path)
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

    /// How the shared store knows this tile.
    ///
    /// An application is a `.application` target so it gets the two-rung lookup —
    /// bundle path first, identifier second — which is what keeps
    /// site-specific-browser wrappers, all reporting one identifier, told apart.
    /// Everything else is keyed by what it is on disk.
    private func target(for tile: DockTile, url: URL) -> IconTarget {
        switch tile.kind {
        case .application:
            return .application(bundleURL: url, bundleIdentifier: tile.bundleIdentifier)
        case .url:
            return .link(url)
        default:
            return .file(url)
        }
    }

    private func appURL(forBundleID bundleID: String?) -> URL? {
        guard let bundleID else { return nil }
        return NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
    }

    // MARK: Trash fullness probe (tier 1 — see TRASH.md)

    /// Tier-1 fullness probe: reads ONLY the user's home Trash. One `readdir` —
    /// cheap, and prompt-free: `~/.Trash` is in the Full-Disk-Access class, which
    /// fails with EPERM rather than showing a consent prompt. Per-volume and
    /// network `.Trashes` are deliberately NOT probed: those are in the
    /// Files & Folders class, where a first attempt can trigger a spontaneous
    /// consent prompt (and a hung share could block the caller). Call off the main
    /// thread. `.unknown` here means "couldn't tell" — almost always TCC — and the
    /// resolver escalates to Finder Automation instead of giving up.
    static func probeTrashFullness() -> TrashState {
        switch trashDirectoryState(TrashLocations.userTrashURL()) {
        case .full: return .full
        case .empty, .missing: return .empty
        case .unreadable: return .unknown
        }
    }

    /// Whether the user's Trash is empty. Missing candidate folders are empty; any
    /// readable candidate containing a real entry makes the Trash full. Kept for the
    /// probe's unit tests; the dock tile uses `probeTrashFullness` (home Trash only).
    static func isTrashEmpty(at trashURLs: [URL]) -> Bool {
        trashState(at: trashURLs) != .full
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
