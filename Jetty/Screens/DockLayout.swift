import CoreGraphics

/// Pure geometry: turns a `DockAnchor` (edge × alignment × offset × inset) plus the
/// dock's content size into the on-screen frame for both the **revealed** and the
/// **hidden** (auto-hidden, slid off-edge) states. All coordinates are AppKit/Cocoa
/// screen coordinates (origin bottom-left, y grows upward). No global state, so it's
/// fully unit-testable. See PLAN.md §4–5.
enum DockLayout {

    /// How many points of the dock peek back on-screen while hidden (a hover hint).
    static let edgeReveal: CGFloat = 2

    // MARK: Content size

    /// The dock's content size for `tileCount` tiles laid along `edge`. Deterministic
    /// (not SwiftUI `fittingSize`), so panel placement never waits on a layout pass.
    static func contentSize(tileCount: Int, iconSize: CGFloat, spacing: CGFloat,
                            padding: CGFloat, edge: DockEdge) -> CGSize {
        let n = CGFloat(max(tileCount, 1))
        let along = n * iconSize + max(n - 1, 0) * spacing + 2 * padding
        let across = iconSize + 2 * padding
        return edge.isHorizontal ? CGSize(width: along, height: across)
                                 : CGSize(width: across, height: along)
    }

    // MARK: Revealed frame

    /// The frame of the fully-revealed dock for `anchor`, sized `contentSize`, within
    /// `visibleFrame`. The dock hugs `anchor.edge` (lifted by `inset`), is aligned
    /// along that edge by `anchor.alignment` (+ `offset`), and is clamped on-screen.
    static func revealedFrame(anchor: DockAnchor, contentSize: CGSize, in visibleFrame: CGRect) -> CGRect {
        let w = min(contentSize.width, visibleFrame.width)
        let h = min(contentSize.height, visibleFrame.height)
        let inset = CGFloat(anchor.inset)
        let offset = CGFloat(anchor.offset)

        switch anchor.edge {
        case .bottom:
            let x = alignAlong(length: w, in: visibleFrame.minX...visibleFrame.maxX,
                               alignment: anchor.alignment, offset: offset, reversed: false)
            return CGRect(x: x, y: visibleFrame.minY + inset, width: w, height: h)
        case .top:
            let x = alignAlong(length: w, in: visibleFrame.minX...visibleFrame.maxX,
                               alignment: anchor.alignment, offset: offset, reversed: false)
            return CGRect(x: x, y: visibleFrame.maxY - inset - h, width: w, height: h)
        case .left:
            // Vertical edge: leading = top, trailing = bottom. `reversed` flips the
            // axis so `leading` maps to the high-y (top) end.
            let y = alignAlong(length: h, in: visibleFrame.minY...visibleFrame.maxY,
                               alignment: anchor.alignment, offset: offset, reversed: true)
            return CGRect(x: visibleFrame.minX + inset, y: y, width: w, height: h)
        case .right:
            let y = alignAlong(length: h, in: visibleFrame.minY...visibleFrame.maxY,
                               alignment: anchor.alignment, offset: offset, reversed: true)
            return CGRect(x: visibleFrame.maxX - inset - w, y: y, width: w, height: h)
        }
    }

    /// Places a segment of `length` within `bounds` per `alignment`, nudged by
    /// `offset` (positive → toward trailing), then clamped to stay fully inside.
    /// When `reversed`, `leading` aligns to the high end (so a vertical dock's
    /// "leading" sits at the top of the screen).
    private static func alignAlong(length: CGFloat, in bounds: ClosedRange<CGFloat>,
                                   alignment: DockAlignment, offset: CGFloat, reversed: Bool) -> CGFloat {
        let lo = bounds.lowerBound
        let hi = bounds.upperBound
        let span = hi - lo
        var origin: CGFloat
        switch alignment {
        case .leading:  origin = reversed ? hi - length : lo
        case .center:   origin = lo + (span - length) / 2
        case .trailing: origin = reversed ? lo : hi - length
        }
        origin += reversed ? -offset : offset
        return clamp(origin, lo, hi - length)
    }

    // MARK: Hidden frame

    /// The off-edge frame for the auto-hidden dock: slid out past `edge` until only
    /// `reveal` points peek back as a hover hint. Only the perpendicular axis moves;
    /// the along-edge position is unchanged.
    static func hiddenFrame(edge: DockEdge, revealedFrame f: CGRect, in visibleFrame: CGRect,
                            reveal: CGFloat = edgeReveal) -> CGRect {
        var frame = f
        switch edge {
        case .bottom: frame.origin.y = visibleFrame.minY - (f.height - reveal)
        case .top:    frame.origin.y = visibleFrame.maxY - reveal
        case .left:   frame.origin.x = visibleFrame.minX - (f.width - reveal)
        case .right:  frame.origin.x = visibleFrame.maxX - reveal
        }
        return frame
    }

    // MARK: Helpers

    static func clamp(_ v: CGFloat, _ lo: CGFloat, _ hi: CGFloat) -> CGFloat {
        guard hi > lo else { return lo }
        return Swift.min(Swift.max(v, lo), hi)
    }
}
