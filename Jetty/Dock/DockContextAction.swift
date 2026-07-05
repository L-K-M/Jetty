import Foundation

/// One entry in a dock tile's synthesized right-click menu. Jetty can't read another
/// app's *custom* Dock menu (that's fetched in-process by the system Dock), so it
/// builds its own from `NSRunningApplication`/`NSWorkspace`. See PLAN.md §7.
struct DockContextAction: Identifiable {
    /// Stable across menu rebuilds (the menu is rebuilt on every right-click), so
    /// SwiftUI's `ForEach` keeps identity/animation continuity. Defaults to the
    /// title — titles are unique within any one menu; if two same-titled actions
    /// ever share a menu, pass an explicit disambiguating `id`.
    let id: String
    let title: String
    var isDestructive: Bool = false
    /// A separator is rendered when `title` is empty and `action` is nil.
    var action: (() -> Void)?

    init(title: String, isDestructive: Bool = false, id: String? = nil,
         action: (() -> Void)? = nil) {
        self.id = id ?? title
        self.title = title
        self.isDestructive = isDestructive
        self.action = action
    }

    /// A fresh separator. Each instance mints its own id so a menu with two
    /// separators never has duplicate `Identifiable` ids.
    static var separator: DockContextAction {
        DockContextAction(title: "", id: "separator-\(UUID().uuidString)")
    }

    var isSeparator: Bool { title.isEmpty && action == nil }
}
