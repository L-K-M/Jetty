import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// The dock's SwiftUI content: a row (or column) of **slots** on a Liquid Glass
/// strip, with continuous pointer-tracking magnification and live drag-to-reorder.
/// Running apps collapse into one slot so they move as a unit and pinned items can
/// sit on either side of them. The glass is a resting-height strip hugging the edge;
/// tiles magnify into transparent headroom above it. See PLAN.md §4, §7, §9.
struct DockView: View {
    @ObservedObject var model: DockModel
    @ObservedObject var preferences: Preferences
    /// This panel's resolved anchor (per-display). The content lays out along
    /// `anchor.edge` — not the global `preferences.edge` — so each display's dock can
    /// use a different edge (BUG-4 / MF-1).
    let anchor: DockAnchor

    @State private var hoveredTileID: String?
    @State private var hoverAlong: CGFloat?            // pointer position along the dock axis (ND-2)
    @State private var draggingSlotID: String?
    @State private var dragAlong: CGFloat = 0
    @State private var dragCross: CGFloat = 0
    @State private var isStripDropTargeted = false     // a file drag is over the dock background

    /// Shared inner padding — also used by `DockLayout.contentSize` so the window
    /// frame and the SwiftUI content agree.
    static let padding: CGFloat = 10

    /// The clock tile's current width factor (widens with a zoomed watch face).
    /// Must match what `DockTileView.tileWidth` and the panel sizing use. The
    /// overflow-scroll state suspends the face zoom, so its rendered width falls
    /// back to the resting factor (`zoomed: false`) — every layout mirror
    /// (centers, slot extents, glows) must use the same `zoomed` flag as the
    /// tiles it lays out, or the reorder/glow math desyncs from what's drawn.
    private func clockWidthFactor(zoomed: Bool) -> CGFloat {
        DockLayout.clockTileWidthFactor(zoom: zoomed ? CGFloat(preferences.effectiveClockZoom) : 1,
                                        face: preferences.clockFace)
    }

    var body: some View {
        let edge = anchor.edge
        let base = CGFloat(preferences.iconSize)
        let spacing = CGFloat(preferences.tileSpacing)
        let resting = base + 2 * Self.padding

        // A GeometryReader so we can tell when the tiles no longer fit the dock's
        // along-axis and switch to a scrollable strip (MF: too many apps).
        GeometryReader { geo in
            let overflows = contentOverflows(edge: edge, base: base, spacing: spacing, available: geo.size)
            ZStack(alignment: edgeAlignment(edge)) {
                glassStrip(edge: edge, thickness: resting, overflows: overflows)
                slotsContainer(edge: edge, base: base, spacing: spacing, resting: resting, overflows: overflows)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: edgeAlignment(edge))
            .contentShape(Rectangle())
            // Continuous pointer tracking → fluid, real-Dock-style magnification (ND-2).
            // Lives on the full-panel container (converted into the slot stack's
            // coordinate space) so magnification keeps tracking through the across
            // headroom the magnified tiles render into — attached to the resting-height
            // slot stack it snapped off as soon as the pointer rode up a zoomed icon.
            .onContinuousHover(coordinateSpace: .local) { phase in
                switch phase {
                case .active(let point):
                    hoverAlong = stackLocalAlong(for: point, in: geo.size, edge: edge,
                                                 base: base, spacing: spacing, overflows: overflows)
                case .ended:
                    hoverAlong = nil
                }
            }
            // Dropping a folder/file on the dock background (not a specific tile) pins it.
            // A tile under the cursor handles its own drop first; this catches the rest.
            .onDrop(of: [.fileURL], isTargeted: $isStripDropTargeted) { providers in
                loadDroppedURLs(from: providers)
                return true
            }
            .overlay { stripDropHighlight(edge: edge, thickness: resting) }
            .onHover { inside in if !inside { hoveredTileID = nil; hoverAlong = nil } }
        }
    }

    /// Whether the tiles' natural along-axis size exceeds the space the dock has — i.e.
    /// the dock has grown to (and been clamped at) the screen edge and can't show every
    /// tile at once.
    private func contentOverflows(edge: DockEdge, base: CGFloat, spacing: CGFloat, available: CGSize) -> Bool {
        guard !model.slots.isEmpty else { return false }
        // Decide overflow from the *zoomed* natural size: the rendered width shrinks
        // to resting in overflow (zoom suspended), so deciding on the zoomed size can
        // only over-trigger, never oscillate.
        let natural = DockLayout.contentSize(tiles: model.tiles.map(\.kind), iconSize: base,
                                             spacing: spacing, padding: Self.padding, edge: edge,
                                             clockWidthFactor: clockWidthFactor(zoomed: true))
        return edge.isHorizontal ? natural.width > available.width + 1
                                 : natural.height > available.height + 1
    }

    /// The tile strip — laid out normally when it fits, or wrapped in a scroll view along
    /// the dock axis when there are too many tiles to fit (native mouse-wheel / trackpad
    /// scrolling). Magnification is suspended in the scrolling state: the tiles are packed
    /// edge-to-edge, so growing them while scrolling would fight the scroll and clip.
    @ViewBuilder
    private func slotsContainer(edge: DockEdge, base: CGFloat, spacing: CGFloat,
                                resting: CGFloat, overflows: Bool) -> some View {
        if overflows {
            let scroll = ScrollView(edge.isHorizontal ? .horizontal : .vertical, showsIndicators: false) {
                slotStack(edge: edge, base: base, spacing: spacing, magnifies: false)
                    .padding(slotStackInsets(edge))
            }
            if edge.isHorizontal {
                scroll.frame(maxWidth: .infinity).frame(height: resting)
            } else {
                scroll.frame(maxHeight: .infinity).frame(width: resting)
            }
        } else {
            slotStack(edge: edge, base: base, spacing: spacing, magnifies: true)
                // No padding on the edge-facing side — each tile reclaims it as tap area
                // so clicks land on icons right up to the screen edge (Fitts' law).
                .padding(slotStackInsets(edge))
        }
    }

    @ViewBuilder
    private func stripDropHighlight(edge: DockEdge, thickness: CGFloat) -> some View {
        if isStripDropTargeted {
            let shape = RoundedRectangle(cornerRadius: CGFloat(preferences.cornerRadius), style: .continuous)
                .stroke(preferences.tintColor, lineWidth: 2)
            Group {
                if edge.isHorizontal {
                    shape.frame(maxWidth: .infinity).frame(height: thickness)
                } else {
                    shape.frame(maxHeight: .infinity).frame(width: thickness)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: edgeAlignment(edge))
            .allowsHitTesting(false)
        }
    }

    /// Loads file URLs from dropped providers and pins them (off the dock background).
    private func loadDroppedURLs(from providers: [NSItemProvider]) {
        var urls: [URL] = []
        let group = DispatchGroup()
        let lock = NSLock()
        for provider in providers {
            group.enter()
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                if let url, url.isFileURL {
                    lock.lock(); urls.append(url); lock.unlock()
                }
                group.leave()
            }
        }
        group.notify(queue: .main) {
            if !urls.isEmpty { model.onAddDroppedItems?(urls) }
        }
    }

    // MARK: Glass strip + decorations

    @ViewBuilder
    private func glassStrip(edge: DockEdge, thickness: CGFloat, overflows: Bool) -> some View {
        let radius = CGFloat(preferences.cornerRadius)
        let bg = GlassBackground(material: preferences.material,
                                 tint: preferences.tintColor,
                                 gradientColor: preferences.gradientColor,
                                 gradientAngle: preferences.gradientAngle,
                                 opacity: preferences.backgroundOpacity,
                                 cornerRadius: radius)
        let sized = Group {
            if edge.isHorizontal {
                bg.frame(maxWidth: .infinity).frame(height: thickness)
            } else {
                bg.frame(maxHeight: .infinity).frame(width: thickness)
            }
        }
        sized
            // The active-app glow lives here, *inside* the strip's clip, so it tints the
            // dock under the running app instead of blooming out past the dock's edges.
            .overlay { activeGlows(edge: edge, thickness: thickness, zoomed: !overflows) }
            .overlay { decorations(cornerRadius: radius) }
            .overlay { if preferences.crtEnabled { CRTScreenOverlay(intensity: preferences.crtIntensity, cornerRadius: radius) } }
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
    }

    // MARK: Active-app glow (ND-8) — clipped to the strip

    @ViewBuilder
    private func activeGlows(edge: DockEdge, thickness: CGFloat, zoomed: Bool) -> some View {
        if preferences.accentGlow {
            let base = CGFloat(preferences.iconSize)
            let spacing = CGFloat(preferences.tileSpacing)
            let centers = tileCenters(base: base, spacing: spacing, zoomed: zoomed)
            // The same along-axis headroom the panel budgets (widest tile), so the
            // glow positions stay aligned with the centered content. In the
            // overflow-scroll state (zoomed == false) magnification is suspended and
            // the stack is leading-aligned — there is no centered headroom to skip.
            let widest = edge.isHorizontal
                ? DockLayout.widestTileFactor(kinds: model.tiles.map(\.kind),
                                              clockWidthFactor: clockWidthFactor(zoomed: zoomed)) : 1
            let extra = zoomed ? DockLayout.magnificationAlongExtra(iconSize: base,
                                                                    magnification: preferences.effectiveMagnification,
                                                                    widestFactor: widest) : 0
            let lead = extra / 2 + Self.padding   // first tile's offset from the strip's leading edge
            ZStack {
                ForEach(model.tiles.filter(isActiveAppTile)) { tile in
                    if let along = centers[tile.id], let color = TileAccent.color(for: tile) {
                        glowDot(color: color, base: base)
                            .position(edge.isHorizontal
                                      ? CGPoint(x: lead + along, y: thickness / 2)
                                      : CGPoint(x: thickness / 2, y: lead + along))
                    }
                }
            }
            .allowsHitTesting(false)
        }
    }

    private func isActiveAppTile(_ tile: DockTile) -> Bool {
        tile.kind == .application && tile.isRunning && tile.isActive && tile.icon != nil
    }

    /// A radial bloom in the icon's dominant colour: a bright core over a broad soft
    /// halo. No hard edge (radial fade); the caller clips it to the strip so it can't
    /// bulge past the dock edge — which lets it be generous without spilling out.
    private func glowDot(color: Color, base: CGFloat) -> some View {
        ZStack {
            Circle()
                .fill(RadialGradient(colors: [color.opacity(0.55), color.opacity(0)],
                                     center: .center, startRadius: 0, endRadius: base * 0.95))
                .frame(width: base * 1.9, height: base * 1.9)
            Circle()
                .fill(RadialGradient(colors: [color.opacity(0.95), color.opacity(0)],
                                     center: .center, startRadius: 0, endRadius: base * 0.5))
                .frame(width: base * 1.0, height: base * 1.0)
        }
    }

    @ViewBuilder
    private func decorations(cornerRadius: CGFloat) -> some View {
        let style = preferences.decorationStyle
        if style != .none {
            Group {
                if style.kind == .ball {
                    BoingBallDecoration(position: preferences.decorationPosition,
                                        cornerRadius: cornerRadius,
                                        diameter: CGFloat(preferences.decorationSize) * 3,
                                        pixelated: style == .amigaPixel)
                } else {
                    PanelDecoration(style: style, position: preferences.decorationPosition,
                                    cornerRadius: cornerRadius, thickness: CGFloat(preferences.decorationSize))
                }
            }
            .opacity(preferences.decorationOpacity)
        }
    }

    // MARK: Slots

    @ViewBuilder
    private func slotStack(edge: DockEdge, base: CGFloat, spacing: CGFloat, magnifies: Bool) -> some View {
        // `magnifies` is false exactly in the overflow-scroll state, where the face
        // zoom is suspended too — the centers must match the rendered tile widths.
        let centers = tileCenters(base: base, spacing: spacing, zoomed: magnifies)
        let slots = Array(model.slots.enumerated())
        Group {
            if edge.isHorizontal {
                HStack(spacing: spacing) {
                    ForEach(slots, id: \.element.id) { index, slot in
                        slotView(slot, slotIndex: index, base: base, spacing: spacing, centers: centers, magnifies: magnifies)
                    }
                }
            } else {
                VStack(spacing: spacing) {
                    ForEach(slots, id: \.element.id) { index, slot in
                        slotView(slot, slotIndex: index, base: base, spacing: spacing, centers: centers, magnifies: magnifies)
                    }
                }
            }
        }
    }

    private func slotView(_ slot: DockSlot, slotIndex: Int, base: CGFloat, spacing: CGFloat,
                          centers: [String: CGFloat], magnifies: Bool) -> some View {
        let isDragged = draggingSlotID == slot.id
        let offset = slotOffset(for: slotIndex, base: base, spacing: spacing, zoomed: magnifies)
        let z = slot.tiles.map { tileScale($0, centers: centers, base: base,
                                           spacing: spacing, magnifies: magnifies) }.max() ?? 1

        return slotTiles(slot, base: base, spacing: spacing, centers: centers, magnifies: magnifies)
            .offset(offset)
            .zIndex(isDragged ? 10_000 : Double(z))
            .animation(isDragged ? nil : .spring(response: 0.26, dampingFraction: 0.85), value: offset)
            .gesture(reorderGesture(for: slot, zoomed: magnifies), including: slot.isReorderable ? .all : .subviews)
    }

    @ViewBuilder
    private func slotTiles(_ slot: DockSlot, base: CGFloat, spacing: CGFloat, centers: [String: CGFloat], magnifies: Bool) -> some View {
        if slot.tiles.count <= 1, let tile = slot.tiles.first {
            tileView(tile, base: base, spacing: spacing, centers: centers, magnifies: magnifies)
        } else if anchor.edge.isHorizontal {
            HStack(spacing: spacing) {
                ForEach(slot.tiles) { tile in tileView(tile, base: base, spacing: spacing, centers: centers, magnifies: magnifies) }
            }
        } else {
            VStack(spacing: spacing) {
                ForEach(slot.tiles) { tile in tileView(tile, base: base, spacing: spacing, centers: centers, magnifies: magnifies) }
            }
        }
    }

    private func tileView(_ tile: DockTile, base: CGFloat, spacing: CGFloat, centers: [String: CGFloat], magnifies: Bool) -> some View {
        let currentScale = tileScale(tile, centers: centers, base: base, spacing: spacing, magnifies: magnifies)
        return DockTileView(
            tile: tile,
            preferences: preferences,
            baseSize: base,
            // Zoomed clocks magnify like any tile — the panel's across headroom
            // budgets for zoom × magnification (DockLayout.clockZoomHeadroom).
            scale: currentScale,
            isHovered: hoveredTileID == tile.id,
            isUnresponsive: model.isUnresponsive(pid: tile.pid),
            edge: anchor.edge,
            // The overflow-scroll state passes magnifies=false; its viewport
            // clips, so the face zoom is suspended alongside magnification.
            allowsClockZoom: magnifies,
            acceptsFileDrop: tileAcceptsFileDrop(tile),
            onTap: { model.onOpenTile?(tile) },
            onHoverChanged: { inside in
                hoveredTileID = inside ? tile.id : (hoveredTileID == tile.id ? nil : hoveredTileID)
                // Running apps peek their windows; folders peek their contents.
                if (tile.kind == .application && tile.isRunning) || tile.kind == .folder {
                    model.onHoverTile?(tile, inside)
                }
            },
            onDropURLs: { urls in model.onDropFiles?(tile, urls) },
            contextActions: { model.onRequestContextActions?(tile) ?? [] },
            onContextMenuPresentationChanged: {
                model.onContextMenuPresentationChanged?(anchor.displayUUID, $0)
            }
        )
        .zIndex(Double(currentScale))
    }

    private func tileAcceptsFileDrop(_ tile: DockTile) -> Bool {
        tile.kind == .application || tile.kind == .trash
    }

    // MARK: Drag-to-reorder

    private func reorderGesture(for slot: DockSlot, zoomed: Bool) -> some Gesture {
        DragGesture(minimumDistance: 10)
            .onChanged { value in
                draggingSlotID = slot.id
                dragAlong = anchor.edge.isHorizontal ? value.translation.width : value.translation.height
                dragCross = anchor.edge.isHorizontal ? value.translation.height : value.translation.width
            }
            .onEnded { _ in
                if !commitDragOutIfNeeded(for: slot) { commitReorder(zoomed: zoomed) }
                draggingSlotID = nil
                dragAlong = 0
                dragCross = 0
            }
    }

    /// If the slot was dragged far enough *off* the dock (perpendicular to its edge),
    /// remove its item instead of reordering — the classic drag-out-to-remove (ND-5).
    /// The running-apps cluster is never removed this way.
    private func commitDragOutIfNeeded(for slot: DockSlot) -> Bool {
        guard !slot.isRunningGroup, let itemID = slot.itemID else { return false }
        let base = CGFloat(preferences.iconSize)
        guard abs(dragCross) > base * 1.6 else { return false }
        model.onDragOutRemove?(itemID)
        return true
    }

    private func slotOffset(for index: Int, base: CGFloat, spacing: CGFloat, zoomed: Bool) -> CGSize {
        guard let draggingSlotID,
              let dragged = model.slots.firstIndex(where: { $0.id == draggingSlotID }) else { return .zero }
        let edge = anchor.edge
        if index == dragged { return vector(along: dragAlong, cross: dragCross, edge: edge) }

        let extents = slotExtents(base: base, spacing: spacing, zoomed: zoomed)
        let target = DockLayout.liveReorderTarget(slotExtents: extents, spacing: spacing,
                                                  draggedIndex: dragged, dragAlong: dragAlong)
        let shift = extents[dragged] + spacing
        if dragged < target, index > dragged, index <= target {
            return vector(along: -shift, cross: 0, edge: edge)
        } else if dragged > target, index >= target, index < dragged {
            return vector(along: shift, cross: 0, edge: edge)
        }
        return .zero
    }

    private func commitReorder(zoomed: Bool) {
        guard let draggingSlotID,
              let dragged = model.slots.firstIndex(where: { $0.id == draggingSlotID }) else { return }
        let base = CGFloat(preferences.iconSize)
        let spacing = CGFloat(preferences.tileSpacing)
        let extents = slotExtents(base: base, spacing: spacing, zoomed: zoomed)
        let target = DockLayout.liveReorderTarget(slotExtents: extents, spacing: spacing,
                                                  draggedIndex: dragged, dragAlong: dragAlong)
        guard target != dragged else { return }
        var ids = model.slots.map { $0.itemID }
        let moved = ids.remove(at: dragged)
        ids.insert(moved, at: target)
        model.onReorder?(ids.compactMap { $0 })
    }

    private func slotExtents(base: CGFloat, spacing: CGFloat, zoomed: Bool) -> [CGFloat] {
        model.slots.map {
            DockLayout.slotExtentAlong(tileKinds: $0.tiles.map(\.kind), baseSize: base,
                                       spacing: spacing, edge: anchor.edge,
                                       clockWidthFactor: clockWidthFactor(zoomed: zoomed))
        }
    }

    // MARK: Magnification (continuous — ND-2)

    /// Converts a pointer position in the panel's local space into the slot stack's
    /// along-axis coordinate space (the space `tileCenters` is built in). Non-overflow
    /// layout centers the stack along the dock axis inside the panel, so the stack's
    /// leading edge sits at `(geo − content) / 2 + padding`.
    private func stackLocalAlong(for point: CGPoint, in size: CGSize, edge: DockEdge,
                                 base: CGFloat, spacing: CGFloat, overflows: Bool) -> CGFloat {
        let pointAlong = edge.isHorizontal ? point.x : point.y
        // In the overflow-scroll state magnification is suspended, so the (scrolled,
        // leading-aligned) conversion would be unused — return the raw coordinate.
        guard !overflows else { return pointAlong }
        let content = DockLayout.contentSize(tiles: model.tiles.map(\.kind), iconSize: base,
                                             spacing: spacing, padding: Self.padding, edge: edge,
                                             clockWidthFactor: clockWidthFactor(zoomed: true))
        let geoAlong = edge.isHorizontal ? size.width : size.height
        let contentAlong = edge.isHorizontal ? content.width : content.height
        return pointAlong - ((geoAlong - contentAlong) / 2 + Self.padding)
    }

    private func scale(center: CGFloat?, base: CGFloat, spacing: CGFloat) -> CGFloat {
        guard preferences.magnificationEnabled, draggingSlotID == nil,
              let hoverAlong, let center else { return 1 }
        let distance = abs(hoverAlong - center)
        return MagnificationCurve.scale(distance: distance, influence: (base + spacing) * 2.2,
                                        maxScale: preferences.effectiveMagnification)
    }

    private func tileScale(_ tile: DockTile, centers: [String: CGFloat], base: CGFloat,
                           spacing: CGFloat, magnifies: Bool) -> CGFloat {
        magnifies ? scale(center: centers[tile.id], base: base, spacing: spacing) : 1
    }

    /// Resting along-axis center of each flat tile (tiles are laid uniformly with
    /// `spacing` since slot and intra-group spacing match), in the slot stack's local
    /// coordinate space — the input the continuous magnification compares against.
    private func tileCenters(base: CGFloat, spacing: CGFloat, zoomed: Bool) -> [String: CGFloat] {
        var map: [String: CGFloat] = [:]
        var cursor: CGFloat = 0
        for slot in model.slots {
            for tile in slot.tiles {
                let extent = DockLayout.tileExtent(kind: tile.kind, baseSize: base, edge: anchor.edge,
                                                   clockWidthFactor: clockWidthFactor(zoomed: zoomed)).along
                map[tile.id] = cursor + extent / 2
                cursor += extent + spacing
            }
        }
        return map
    }

    // MARK: Helpers

    private func vector(along: CGFloat, cross: CGFloat, edge: DockEdge) -> CGSize {
        edge.isHorizontal ? CGSize(width: along, height: cross) : CGSize(width: cross, height: along)
    }

    private func edgeAlignment(_ edge: DockEdge) -> Alignment {
        switch edge {
        case .bottom: return .bottom
        case .top: return .top
        case .left: return .leading
        case .right: return .trailing
        }
    }

    /// Inner padding around the tiles — full on every side *except* the one facing the
    /// screen edge, which each tile reclaims as tap area (Fitts' law). The total tile
    /// block size is unchanged, so `DockLayout.contentSize` still matches.
    private func slotStackInsets(_ edge: DockEdge) -> EdgeInsets {
        let p = Self.padding
        switch edge {
        case .bottom: return EdgeInsets(top: p, leading: p, bottom: 0, trailing: p)
        case .top:    return EdgeInsets(top: 0, leading: p, bottom: p, trailing: p)
        case .left:   return EdgeInsets(top: p, leading: 0, bottom: p, trailing: p)
        case .right:  return EdgeInsets(top: p, leading: p, bottom: p, trailing: 0)
        }
    }
}
