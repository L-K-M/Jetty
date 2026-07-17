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
                            padding: CGFloat, edge: DockEdge,
                            clockWidthFactor: CGFloat = DockItemKind.clock.tileWidthFactor) -> CGSize {
        guard !kinds.isEmpty else {
            return contentSize(tileCount: 1, iconSize: iconSize, spacing: spacing, padding: padding, edge: edge)
        }
        let extents = kinds.map { tileExtent(kind: $0, baseSize: iconSize, edge: edge,
                                             clockWidthFactor: clockWidthFactor) }
        let along = extents.reduce(0) { $0 + $1.along }
            + CGFloat(kinds.count - 1) * spacing + 2 * padding
        let across = (extents.map { $0.across }.max() ?? iconSize) + 2 * padding
        return edge.isHorizontal ? CGSize(width: along, height: across)
                                 : CGSize(width: across, height: along)
    }

    /// A single tile's size split into the dimension *along* the dock and the one
    /// *across* it, for `edge`. Mirrors `DockTileView`'s per-kind frame: a horizontal
    /// separator is a thin 12pt gap, the clock tile is `clockWidthFactor` wide (its
    /// resting 1.6×, or wider when a zoomed face needs the room — horizontal docks
    /// only), everything else is a `baseSize` square (tile height is always
    /// `baseSize`). **Keep in sync with `DockTileView.tileWidth`.**
    static func tileExtent(kind: DockItemKind, baseSize: CGFloat, edge: DockEdge,
                           clockWidthFactor: CGFloat = DockItemKind.clock.tileWidthFactor)
        -> (along: CGFloat, across: CGFloat) {
        let frameWidth: CGFloat
        switch kind {
        case .separator: frameWidth = edge.isHorizontal ? 12 : baseSize
        case .clock where edge.isHorizontal: frameWidth = baseSize * clockWidthFactor
        default: frameWidth = baseSize * kind.tileWidthFactor
        }
        let frameHeight = baseSize
        // Horizontal dock: along-axis is width. Vertical dock: along-axis is height.
        return edge.isHorizontal ? (along: frameWidth, across: frameHeight)
                                 : (along: frameHeight, across: frameWidth)
    }

    /// The clock tile's along-edge width factor for `face` zoomed to `zoom`: the
    /// resting 1.6× until the face (plus a little slack) outgrows it, then wide
    /// enough to hold the face so it never overlaps neighboring tiles — or, for
    /// the LCD, squashes. The square analog dials are 0.92 × zoom of the icon
    /// size; the LCD's landscape resin case is 1.35 × its `zoom`-scaled height
    /// (`LCDClockFace`'s `caseH * 1.35` — keep in sync). Pure, unit-tested.
    /// **Keep `DockTileView.tileWidth` and `ClockWidgetView` driven by this.**
    static func clockTileWidthFactor(zoom: CGFloat, face: ClockFaceStyle = .classic) -> CGFloat {
        let faceWidth = face == .lcd ? 1.35 * zoom : 0.92 * zoom
        return max(DockItemKind.clock.tileWidthFactor, faceWidth + 0.08)
    }

    /// The widest tile's along-edge width factor among `kinds` (the clock uses
    /// `clockWidthFactor`, which may exceed its resting 1.6× when zoomed). The
    /// along-axis magnification headroom scales with this so a wide end tile
    /// (now-playing, a zoomed clock) doesn't clip at the window ends. Pure.
    static func widestTileFactor(kinds: [DockItemKind], clockWidthFactor: CGFloat) -> CGFloat {
        kinds.map { $0 == .clock ? clockWidthFactor : $0.tileWidthFactor }.max() ?? 1
    }

    /// The along-axis window headroom for hover magnification: a magnified tile
    /// scales about the edge anchor, so its width grows about its centre by
    /// `(magnification − 1) × width` — budget for the widest tile, split half per
    /// window end by the centered content. Pure, unit-tested.
    static func magnificationAlongExtra(iconSize: CGFloat, magnification: CGFloat,
                                        widestFactor: CGFloat) -> CGFloat {
        max(0, (magnification - 1) * iconSize * widestFactor)
    }

    /// Extra across-axis window headroom needed for a zoomed clock face
    /// (Widgets ▸ Clock ▸ Face size). The zoomed face box is at most
    /// `iconSize * zoom` across (the LCD; analog dials are 0.92× of that), sits
    /// `0.04 * iconSize` off the edge-facing side of the tile
    /// (`ClockWidgetView`'s edge padding — keep in sync), scales by the hover
    /// `magnification` about the edge anchor, and the resting strip is
    /// `iconSize + 2 * padding` — whatever pokes past the strip needs window
    /// room so it isn't clipped at the panel bounds. Pure, unit-tested.
    static func clockZoomHeadroom(iconSize: CGFloat, padding: CGFloat, zoom: CGFloat,
                                  magnification: CGFloat = 1) -> CGFloat {
        max(0, iconSize * (zoom + 0.04) * max(magnification, 1) - (iconSize + padding))
    }

    /// Across-axis window headroom so a hover label floating toward screen center
    /// stays inside the panel: `DockTileView` offsets the capsule `0.75 × iconSize`
    /// out from the tile — keep in sync — and the capsule itself needs ~16pt.
    /// Without this the clipped container shaves the label at high magnification
    /// and hides it entirely when magnification is off. Pure, unit-tested.
    static func labelHeadroom(iconSize: CGFloat) -> CGFloat {
        iconSize * 0.75 + 16
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

    /// The region the pointer may occupy while a revealed dock stays up: the revealed
    /// frame grown by `slop` points (the user's hide-distance preference), extended to
    /// the physical screen edge on the dock's side. The extension matters whenever the
    /// dock is inset from its edge: the hard-edge reveal fires instantly at the
    /// physical edge, so treating the strip between the panel and that edge as
    /// "outside" would make the dock flap reveal/hide while the pointer rests there.
    static func keepRevealedFrame(revealed: CGRect, screenFrame: CGRect, edge: DockEdge,
                                  slop: CGFloat) -> CGRect {
        var r = revealed.insetBy(dx: -slop, dy: -slop)
        switch edge {
        case .bottom:
            let gap = r.minY - screenFrame.minY
            if gap > 0 { r.origin.y -= gap; r.size.height += gap }
        case .top:
            let gap = screenFrame.maxY - r.maxY
            if gap > 0 { r.size.height += gap }
        case .left:
            let gap = r.minX - screenFrame.minX
            if gap > 0 { r.origin.x -= gap; r.size.width += gap }
        case .right:
            let gap = screenFrame.maxX - r.maxX
            if gap > 0 { r.size.width += gap }
        }
        return r
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

    // MARK: Edge-crossing reveal (multi-display seams)

    /// Whether `point` (global Cocoa coords) sits just **past** the dock's physical edge:
    /// within `band` points *outside* `screenFrame` across `edge`, and over the dock's
    /// along-extent (`dockFrame` widened by `margin`). On a display stacked against another
    /// this catches the cursor that crossed the internal seam onto the neighbour, so the
    /// dock stays reachable; on a true screen boundary the region is off-desktop and the
    /// cursor can never reach it, so it never fires (no regression for non-stacked layouts).
    /// Pure, so the reveal geometry is unit-tested.
    static func pointerCrossedEdge(_ point: CGPoint, screenFrame f: CGRect, dockFrame r: CGRect,
                                   edge: DockEdge, band: CGFloat, margin m: CGFloat) -> Bool {
        switch edge {
        case .bottom:
            return point.y < f.minY && point.y >= f.minY - band
                && point.x >= r.minX - m && point.x <= r.maxX + m
        case .top:
            return point.y > f.maxY && point.y <= f.maxY + band
                && point.x >= r.minX - m && point.x <= r.maxX + m
        case .left:
            return point.x < f.minX && point.x >= f.minX - band
                && point.y >= r.minY - m && point.y <= r.maxY + m
        case .right:
            return point.x > f.maxX && point.x <= f.maxX + band
                && point.y >= r.minY - m && point.y <= r.maxY + m
        }
    }

    // MARK: Drag-to-reorder (slot-based)

    /// The along-axis extent of a slot whose tiles have these `kinds`, laid out with
    /// `spacing` between them (a running-apps slot has several tiles; everything else
    /// has one). Pure, so the live-reorder math is unit-tested.
    static func slotExtentAlong(tileKinds kinds: [DockItemKind], baseSize: CGFloat,
                                spacing: CGFloat, edge: DockEdge,
                                clockWidthFactor: CGFloat = DockItemKind.clock.tileWidthFactor) -> CGFloat {
        guard !kinds.isEmpty else { return 0 }
        let sum = kinds.reduce(CGFloat(0)) {
            $0 + tileExtent(kind: $1, baseSize: baseSize, edge: edge,
                            clockWidthFactor: clockWidthFactor).along
        }
        return sum + CGFloat(kinds.count - 1) * spacing
    }

    /// The destination index the dragged slot should occupy, given every slot's
    /// along-axis `slotExtents` (in current order), the `spacing` between slots, the
    /// `draggedIndex`, and the pointer's along-axis drag distance `dragAlong`. Used
    /// both for the live gap-opening preview and for the committed move. Pure. §7.
    static func liveReorderTarget(slotExtents: [CGFloat], spacing: CGFloat,
                                  draggedIndex: Int, dragAlong: CGFloat) -> Int {
        guard slotExtents.indices.contains(draggedIndex) else { return draggedIndex }
        var centers: [CGFloat] = []
        var cursor: CGFloat = 0
        for extent in slotExtents {
            centers.append(cursor + extent / 2)
            cursor += extent + spacing
        }
        let movedCenter = centers[draggedIndex] + dragAlong
        var target = 0
        for i in slotExtents.indices where i != draggedIndex {
            if centers[i] < movedCenter { target += 1 }
        }
        return target
    }

    // MARK: Helpers

    static func clamp(_ v: CGFloat, _ lo: CGFloat, _ hi: CGFloat) -> CGFloat {
        guard hi > lo else { return lo }
        return Swift.min(Swift.max(v, lo), hi)
    }
}
