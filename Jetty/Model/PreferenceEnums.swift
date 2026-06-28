import Foundation

/// The dock background material. Glass variants render real Liquid Glass on macOS
/// 26 (with a blur fallback below) — see `GlassBackground`.
enum DockMaterial: String, Codable, CaseIterable, Identifiable {
    case liquidGlass
    case glassClear
    case glassTinted
    case solid
    case gradient

    var id: String { rawValue }

    var label: String {
        switch self {
        case .liquidGlass: return "Liquid Glass"
        case .glassClear: return "Liquid Glass (Clear)"
        case .glassTinted: return "Liquid Glass (Tinted)"
        case .solid: return "Solid"
        case .gradient: return "Gradient"
        }
    }
}

/// How a running app is marked on its tile.
enum IndicatorStyle: String, Codable, CaseIterable, Identifiable {
    case dot, bar, underline, none
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
}

/// What brings the auto-hidden dock back.
enum RevealTrigger: String, Codable, CaseIterable, Identifiable {
    case edgeHover
    case hotkey
    case both

    var id: String { rawValue }

    var label: String {
        switch self {
        case .edgeHover: return "Pointer at edge"
        case .hotkey: return "Hotkey"
        case .both: return "Either"
        }
    }

    var allowsEdgeHover: Bool { self == .edgeHover || self == .both }
    var allowsHotkey: Bool { self == .hotkey || self == .both }
}

/// How the hover window-peek presents an app's windows.
enum WindowPreviewMode: String, Codable, CaseIterable, Identifiable {
    /// No hover preview at all.
    case off
    /// A list of window names — needs **no** permission (names come from Accessibility
    /// when granted, else a generic "Window N"); clicking raises (or activates the app).
    case names
    /// Live window thumbnails — needs **Screen Recording**.
    case thumbnails

    var id: String { rawValue }

    var label: String {
        switch self {
        case .off: return "Off"
        case .names: return "Window names"
        case .thumbnails: return "Live thumbnails"
        }
    }

    var capturesThumbnails: Bool { self == .thumbnails }
}

/// Which displays get a Jetty dock.
enum DisplayScope: String, Codable, CaseIterable, Identifiable {
    case mainOnly
    case allDisplays

    var id: String { rawValue }

    var label: String {
        switch self {
        case .mainOnly: return "Main display only"
        case .allDisplays: return "All displays"
        }
    }
}
