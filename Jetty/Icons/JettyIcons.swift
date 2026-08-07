import AppKit
import PictKit

/// Jetty's side of the shared icon store.
///
/// The dock draws app icons, and on macOS 26 `NSWorkspace.icon(forFile:)` hands
/// back the squircle-masked composite for every one of them. Jetty draws its own
/// tiles, so it is no more obliged to show that than Zap's switcher is — and now
/// that the store and the resolution ladder live in `PictKit`, it doesn't have to
/// implement any of it either.
///
/// Deliberately small. Jetty has no icon-size slider, no bleed setting and no
/// search UI, so there is nothing here but the options a dock wants, a watcher, and
/// a way to ask whether Pict is around.
final class JettyIcons {

    static let shared = JettyIcons()

    let store: IconStore
    /// Thread-safe by construction — `IconResolver` guards its cache with a lock and
    /// does its work on its own queue — so this type carries no actor isolation and
    /// `icon(for:)` is callable from wherever an icon is needed, including the
    /// static resolution helpers that draw a slot.
    let resolver: IconResolver

    /// Called when another app changes the store, so the dock can drop its icon
    /// cache. Set by `DockModel`, which owns that cache.
    var onStoreChanged: (() -> Void)?

    private var watcher: IconStoreWatcher?
    private var screenObserver: NSObjectProtocol?

    private init(store: IconStore = IconStore()) {
        self.store = store
        // A dock tile sits in a grid, so `bleed: 0`: free-form artwork spilling past
        // its cell is the look Zap's switcher is after and exactly the wrong one
        // here, where the neighbour is 8 points away. No baked shadow either — the
        // dock panel already has its own material behind the tiles.
        self.resolver = IconResolver(options: .plain(pointSize: Self.tilePointSize,
                                                     scale: Self.backingScale()),
                                     store: store)
        watch()
        watchScreens()
    }

    deinit {
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
    }

    /// The largest a tile is drawn. Icons are cached at one size rather than
    /// tracking a slider, because Jetty has no slider — a tile's size comes from the
    /// dock's own layout, and the spread is small enough that one cache is right.
    private static let tilePointSize: Double = 64

    private static func backingScale() -> CGFloat {
        NSScreen.screens.map(\.backingScaleFactor).max() ?? 2
    }

    /// Plugging in a sharper display makes every cached icon too soft for it, and
    /// nothing else here would notice. `update(_:)` compares before acting, so an
    /// irrelevant display change costs a comparison.
    private func watchScreens() {
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.resolver.update(.plain(pointSize: Self.tilePointSize,
                                         scale: Self.backingScale()))
        }
    }

    /// The icon to draw for `target`, or `nil` to fall back to what the system says.
    /// A dictionary lookup; a miss warms in the background and returns `nil`.
    func icon(for target: IconTarget) -> NSImage? {
        resolver.icon(for: target)
    }

    private func watch() {
        watcher = IconStoreWatcher(store: store) { [weak self] in
            self?.resolver.invalidate()
            self?.onStoreChanged?()
        }
        watcher?.start()
    }
}
