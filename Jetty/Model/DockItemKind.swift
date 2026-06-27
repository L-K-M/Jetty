import Foundation
import CoreGraphics

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
    /// A sentinel marking *where* the running-but-not-pinned apps appear in the dock.
    /// It renders as the live running-apps cluster (one reorderable unit), so the
    /// user can place pinned items on either side of it (e.g. the clock to its
    /// right). See PLAN.md §6–7.
    case runningApps
    // Live "info" widget tiles — same architecture as the clock (ND-3).
    case battery
    case systemMonitor
    case worldClock
    case pomodoro
    case weather
    case nowPlaying
}

extension DockItemKind {
    /// The tile's along-edge width as a multiple of the base icon size. Wide info
    /// widgets read like the clock; everything else is a square. Separators are a
    /// fixed thin gap and are special-cased by the callers, so their factor is
    /// unused. **Keep `DockLayout.tileExtent` and `DockTileView.tileWidth` driven by
    /// this so panel sizing and rendering never disagree.**
    var tileWidthFactor: CGFloat {
        switch self {
        case .nowPlaying: return 2.4
        case .clock, .systemMonitor, .worldClock, .weather: return 1.6
        case .battery, .pomodoro: return 1.4
        default: return 1.0
        }
    }

    /// Built-in live widgets render with their own SwiftUI view (no file icon).
    var isLiveWidget: Bool {
        switch self {
        case .clock, .battery, .systemMonitor, .worldClock, .pomodoro, .weather, .nowPlaying: return true
        default: return false
        }
    }
}

/// How a `.folder` tile presents its contents when clicked.
enum FolderStackStyle: String, Codable, CaseIterable, Identifiable {
    case fan, grid, list
    var id: String { rawValue }
}
