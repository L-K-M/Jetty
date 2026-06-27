import Foundation

/// What a dock tile *is*. Apps, files/folders, and links are launchable targets;
/// the rest are built-in tiles (a divider, the Trash, the date/time widget, and
/// the Start-menu-style Jetty Menu button). See PLAN.md §6.
enum DockItemKind: String, Codable {
    case application
    case file
    case folder
    case url
    case separator
    case trash
    case clock
    case jettyMenu
}

/// How a `.folder` tile presents its contents when clicked.
enum FolderStackStyle: String, Codable, CaseIterable, Identifiable {
    case fan, grid, list
    var id: String { rawValue }
}
