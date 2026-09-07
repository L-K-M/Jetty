import Foundation

/// A dock tile's own geometry: how wide its frame is, and how much edge-facing padding
/// turns the gap to the screen edge into tap target.
///
/// This is the **single source of truth** for tile width. `DockLayout.tileExtent` (which
/// sizes the panel) and `DockTileView` (which draws the tile) previously each carried
/// their own copy of the same three-case switch, joined by a "keep in sync" comment;
/// JP-03 gave them shared *constants* and left the duplicated logic. They now both call
/// `frameWidth`, so agreeing is structural rather than remembered.
///
/// Pure and portable — no SwiftUI, no AppKit — which is also why the padding is
/// expressed as plain numbers the view converts, rather than as `EdgeInsets`.
enum DockTileGeometry {

    /// A tile's frame width for `edge`: a horizontal separator is a thin gap, the clock
    /// is `clockWidthFactor` wide on horizontal docks only, everything else is
    /// `baseSize × kind.tileWidthFactor`. Height is always `baseSize`, so the caller
    /// that needs an along/across split (`DockLayout.tileExtent`) derives it from this.
    ///
    /// `clockWidthFactor` is a parameter rather than a lookup because the two callers
    /// want different values from the same rule: the panel sizes against the clock's
    /// resting factor, while the view passes the zoom-aware factor — and passes the
    /// resting one anyway while overflow-scrolling, where the face renders unzoomed.
    static func frameWidth(kind: DockItemKind, baseSize: CGFloat, edge: DockEdge,
                           clockWidthFactor: CGFloat) -> CGFloat {
        switch kind {
        case .separator: return edge.isHorizontal ? DockLayout.separatorExtent : baseSize
        case .clock where edge.isHorizontal: return baseSize * clockWidthFactor
        default: return baseSize * kind.tileWidthFactor
        }
    }

    /// Padding on the edge-facing side only, in the order SwiftUI's `EdgeInsets` takes.
    /// Reclaiming the dead strip between the icon and the screen edge as tap target is
    /// what lets a click slammed to the very edge still hit the icon above it (Fitts'
    /// law); `DockView` drops its matching edge-side padding so the dock's overall size
    /// is unchanged.
    struct EdgePadding: Equatable {
        var top: CGFloat = 0
        var leading: CGFloat = 0
        var bottom: CGFloat = 0
        var trailing: CGFloat = 0
    }

    static func edgePadding(edge: DockEdge, padding: CGFloat) -> EdgePadding {
        switch edge {
        case .bottom: return EdgePadding(bottom: padding)
        case .top:    return EdgePadding(top: padding)
        case .left:   return EdgePadding(leading: padding)
        case .right:  return EdgePadding(trailing: padding)
        }
    }
}
