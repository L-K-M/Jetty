import Foundation

/// Which screen edge the dock hugs.
enum DockEdge: String, Codable, CaseIterable, Identifiable {
    case bottom, top, left, right

    var id: String { rawValue }

    var label: String {
        switch self {
        case .bottom: return "Bottom"
        case .top: return "Top"
        case .left: return "Left"
        case .right: return "Right"
        }
    }

    /// Bottom/top docks lay their tiles in a **row**; left/right in a **column**.
    var isHorizontal: Bool { self == .bottom || self == .top }
    var isVertical: Bool { !isHorizontal }
}

/// Where the dock sits *along* its edge. The real Dock only offers `center`;
/// Jetty's headline positioning win is letting you pick `leading` / `trailing`
/// too (e.g. bottom-edge + trailing = "bottom-right"). See PLAN.md §5.
enum DockAlignment: String, Codable, CaseIterable, Identifiable {
    case leading, center, trailing

    var id: String { rawValue }

    var label: String {
        switch self {
        case .leading: return "Leading"
        case .center: return "Center"
        case .trailing: return "Trailing"
        }
    }
}
