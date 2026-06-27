import CoreGraphics

/// Pure geometry: turns a `DockAnchor` (edge × alignment × offset × inset) plus the
/// dock's content size into the on-screen frame for both the **revealed** and the
/// **hidden** (auto-hidden, slid off-edge) states. All coordinates are AppKit/Cocoa
/// screen coordinates (origin bottom-left, y grows upward). No global state, so it's
/// fully unit-testable. See PLAN.md §4–5.
enum DockLayout {

    /// How many points of the dock peek back on-screen while hidden. `0` hides it
    /// completely — reveal is triggered by the pointer reaching the *screen* edge
    /// (see `EdgeHoverMonitor` / `DockPanelController.pointerInRevealZone`), not by a
    /// visible sliver, so no pixels of the dock show while hidden.
    static let edgeReveal: CGFloat = 0

    // MARK: Content size

    /// The dock's content size for `tileCount` **uniform** (`iconSize`-square) tiles
    /// laid along `edge`. Deterministic (not SwiftUI `fittingSize`), so panel
    /// placement never waits on a layout pass.
    ///
    /// Use `contentSize(tiles:…)` instead when the dock contains variable-width tiles
    /// (the clock is 1.6× wide, a horizontal separator is a thin 12pt gap); this
    /// uniform form mis-sizes those and is kept for the all-square case and tests.
    static func contentSize(tileCount: Int, iconSize: CGFloat, spacing: CGFloat,
                            padding: CGFloat, edge: DockEdge) -> CGSize {
        let n = CGFloat(max(tileCount, 1))
        let along = n * iconSize + max(n - 1, 0) * spacing + 2 * padding
        let across = iconSize + 2 * padding
        return edge.isHorizontal ? CGSize(width: along, height: across)
                                 : CGSize(width: across, height: along)
    }

    /// The dock's content size for an actual list of tile `kinds`, accounting for
    /// the clock tile (1.6× wide) and thin separators. The *along*-edge dimension
    /// sums each tile's extent; the *across* dimension fits the widest tile. This is
    /// what keeps the `NSPanel` exactly as wide as its SwiftUI content, so the clock
    /// never clips and separators don't leave dead glass (BUG-1).
    static func contentSize(tiles kinds: [DockItemKind], iconSize: CGFloat, spacing: CGFloat,
                            padding: CGFloat, edge: DockEdge) -> CGSize {
        guard !kinds.isEmpty else {
            return contentSize(tileCount: 1, iconSize: iconSize, spacing: spacing, padding: padding, edge: edge)
        }
        let extents = kinds.map { tileExtent(kind: $0, baseSize: iconSize, edge: edge) }
        let along = extents.reduce(0) { $0 + $1.along }
            + CGFloat(kinds.count - 1) * spacing + 2 * padding
        let across = (extents.map { $0.across }.max() ?? iconSize) + 2 * padding
        return edge.isHorizontal ? CGSize(width: along, height: across)
                                 : CGSize(width: across, height: along)
    }

    /// A single tile's size split into the dimension *along* the dock and the one
    /// *across* it, for `edge`. Mirrors `DockTileView`'s per-kind frame: a horizontal
    /// separator is a thin 12pt gap, the clock tile is 1.6× wide, everything else is
    /// a `baseSize` square (tile height is always `baseSize`). **Keep in sync with
    /// `DockTileView.tileWidth`.**
    static func tileExtent(kind: DockItemKind, baseSize: CGFloat, edge: DockEdge) -> (along: CGFloat, across: CGFloat) {
        let frameWidth: CGFloat
        switch kind {
        case .separator: frameWidth = edge.isHorizontal ? 12 : baseSize
        case .clock:     frameWidth = baseSize * 1.6
        default:         frameWidth = baseSize
        }
        let frameHeight = baseSize
        // Horizontal dock: along-axis is width. Vertical dock: along-axis is height.
        return edge.isHorizontal ? (along: frameWidth, across: frameHeight)
                                 : (along: frameHeight, across: frameWidth)
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

    // MARK: Drag-to-reorder

    /// The destination pinned index for a drag of `translationPrimary` points (along
    /// the dock's axis) starting from `currentIndex`, given the per-tile `step`
    /// (icon size + spacing) and the count of reorderable `pinnedCount` tiles. Pure,
    /// so it's unit-tested. See PLAN.md §7.
    static func reorderTargetIndex(currentIndex: Int, translationPrimary: CGFloat,
                                   step: CGFloat, pinnedCount: Int) -> Int {
        guard step > 0, pinnedCount > 0 else { return currentIndex }
        let delta = Int((translationPrimary / step).rounded())
        return Swift.max(0, Swift.min(currentIndex + delta, pinnedCount - 1))
    }

    // MARK: Helpers

    static func clamp(_ v: CGFloat, _ lo: CGFloat, _ hi: CGFloat) -> CGFloat {
        guard hi > lo else { return lo }
        return Swift.min(Swift.max(v, lo), hi)
    }
}
