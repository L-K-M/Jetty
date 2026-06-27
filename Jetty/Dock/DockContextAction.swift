import Foundation

/// One entry in a dock tile's synthesized right-click menu. Jetty can't read another
/// app's *custom* Dock menu (that's fetched in-process by the system Dock), so it
/// builds its own from `NSRunningApplication`/`NSWorkspace`. See PLAN.md §7.
struct DockContextAction: Identifiable {
    let id = UUID()
    let title: String
    var isDestructive: Bool = false
    /// A separator is rendered when `title` is empty and `action` is nil.
    var action: (() -> Void)?

    static let separator = DockContextAction(title: "", isDestructive: false, action: nil)
    var isSeparator: Bool { title.isEmpty && action == nil }
}
