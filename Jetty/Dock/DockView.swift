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

    var body: some View {
        let edge = anchor.edge
        let base = CGFloat(preferences.iconSize)
        let spacing = CGFloat(preferences.tileSpacing)
        let resting = base + 2 * Self.padding

        ZStack(alignment: edgeAlignment(edge)) {
            glassStrip(edge: edge, thickness: resting)
            slotStack(edge: edge, base: base, spacing: spacing)
                .padding(Self.padding)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: edgeAlignment(edge))
        .contentShape(Rectangle())
        // Dropping a folder/file on the dock background (not a specific tile) pins it.
        // A tile under the cursor handles its own drop first; this catches the rest.
        .onDrop(of: [.fileURL], isTargeted: $isStripDropTargeted) { providers in
            loadDroppedURLs(from: providers)
            return true
        }
        .overlay { stripDropHighlight(edge: edge, thickness: resting) }
        .onHover { inside in if !inside { hoveredTileID = nil; hoverAlong = nil } }
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
    private func glassStrip(edge: DockEdge, thickness: CGFloat) -> some View {
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
            .overlay { decorations(cornerRadius: radius) }
            .overlay { if preferences.crtEnabled { CRTScreenOverlay(intensity: preferences.crtIntensity, cornerRadius: radius) } }
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
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
    private func slotStack(edge: DockEdge, base: CGFloat, spacing: CGFloat) -> some View {
        let centers = tileCenters(base: base, spacing: spacing)
        let slots = Array(model.slots.enumerated())
        Group {
            if edge.isHorizontal {
                HStack(spacing: spacing) {
                    ForEach(slots, id: \.element.id) { index, slot in
                        slotView(slot, slotIndex: index, base: base, spacing: spacing, centers: centers)
                    }
                }
            } else {
                VStack(spacing: spacing) {
                    ForEach(slots, id: \.element.id) { index, slot in
                        slotView(slot, slotIndex: index, base: base, spacing: spacing, centers: centers)
                    }
                }
            }
        }
        // Continuous pointer tracking → fluid, real-Dock-style magnification (ND-2).
        .onContinuousHover(coordinateSpace: .local) { phase in
            switch phase {
            case .active(let point): hoverAlong = edge.isHorizontal ? point.x : point.y
            case .ended: hoverAlong = nil
            }
        }
    }

    private func slotView(_ slot: DockSlot, slotIndex: Int, base: CGFloat, spacing: CGFloat,
                          centers: [String: CGFloat]) -> some View {
        let isDragged = draggingSlotID == slot.id
        let offset = slotOffset(for: slotIndex, base: base, spacing: spacing)

        return slotTiles(slot, base: base, spacing: spacing, centers: centers)
            .offset(offset)
            .zIndex(isDragged ? 1 : 0)
            .animation(isDragged ? nil : .spring(response: 0.26, dampingFraction: 0.85), value: offset)
            .gesture(reorderGesture(for: slot), including: slot.isReorderable ? .all : .subviews)
    }

    @ViewBuilder
    private func slotTiles(_ slot: DockSlot, base: CGFloat, spacing: CGFloat, centers: [String: CGFloat]) -> some View {
        if slot.tiles.count <= 1, let tile = slot.tiles.first {
            tileView(tile, base: base, spacing: spacing, centers: centers)
        } else if anchor.edge.isHorizontal {
            HStack(spacing: spacing) {
                ForEach(slot.tiles) { tile in tileView(tile, base: base, spacing: spacing, centers: centers) }
            }
        } else {
            VStack(spacing: spacing) {
                ForEach(slot.tiles) { tile in tileView(tile, base: base, spacing: spacing, centers: centers) }
            }
        }
    }

    private func tileView(_ tile: DockTile, base: CGFloat, spacing: CGFloat, centers: [String: CGFloat]) -> some View {
        DockTileView(
            tile: tile,
            preferences: preferences,
            baseSize: base,
            scale: scale(center: centers[tile.id], base: base, spacing: spacing),
            isHovered: hoveredTileID == tile.id,
            edge: anchor.edge,
            onTap: { model.onOpenTile?(tile) },
            onHoverChanged: { inside in hoveredTileID = inside ? tile.id : (hoveredTileID == tile.id ? nil : hoveredTileID) },
            onDropURLs: { urls in model.onDropFiles?(tile, urls) },
            contextActions: { model.onRequestContextActions?(tile) ?? [] }
        )
    }

    // MARK: Drag-to-reorder

    private func reorderGesture(for slot: DockSlot) -> some Gesture {
        DragGesture(minimumDistance: 10)
            .onChanged { value in
                draggingSlotID = slot.id
                dragAlong = anchor.edge.isHorizontal ? value.translation.width : value.translation.height
                dragCross = anchor.edge.isHorizontal ? value.translation.height : value.translation.width
            }
            .onEnded { _ in
                if !commitDragOutIfNeeded(for: slot) { commitReorder() }
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

    private func slotOffset(for index: Int, base: CGFloat, spacing: CGFloat) -> CGSize {
        guard let draggingSlotID,
              let dragged = model.slots.firstIndex(where: { $0.id == draggingSlotID }) else { return .zero }
        let edge = anchor.edge
        if index == dragged { return vector(along: dragAlong, cross: dragCross, edge: edge) }

        let extents = slotExtents(base: base, spacing: spacing)
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

    private func commitReorder() {
        guard let draggingSlotID,
              let dragged = model.slots.firstIndex(where: { $0.id == draggingSlotID }) else { return }
        let base = CGFloat(preferences.iconSize)
        let spacing = CGFloat(preferences.tileSpacing)
        let extents = slotExtents(base: base, spacing: spacing)
        let target = DockLayout.liveReorderTarget(slotExtents: extents, spacing: spacing,
                                                  draggedIndex: dragged, dragAlong: dragAlong)
        guard target != dragged else { return }
        var ids = model.slots.map { $0.itemID }
        let moved = ids.remove(at: dragged)
        ids.insert(moved, at: target)
        model.onReorder?(ids.compactMap { $0 })
    }

    private func slotExtents(base: CGFloat, spacing: CGFloat) -> [CGFloat] {
        model.slots.map {
            DockLayout.slotExtentAlong(tileKinds: $0.tiles.map(\.kind), baseSize: base,
                                       spacing: spacing, edge: anchor.edge)
        }
    }

    // MARK: Magnification (continuous — ND-2)

    private func scale(center: CGFloat?, base: CGFloat, spacing: CGFloat) -> CGFloat {
        guard preferences.magnificationEnabled, draggingSlotID == nil,
              let hoverAlong, let center else { return 1 }
        let distance = abs(hoverAlong - center)
        return MagnificationCurve.scale(distance: distance, influence: (base + spacing) * 2.2,
                                        maxScale: preferences.effectiveMagnification)
    }

    /// Resting along-axis center of each flat tile (tiles are laid uniformly with
    /// `spacing` since slot and intra-group spacing match), in the slot stack's local
    /// coordinate space — the input the continuous magnification compares against.
    private func tileCenters(base: CGFloat, spacing: CGFloat) -> [String: CGFloat] {
        var map: [String: CGFloat] = [:]
        var cursor: CGFloat = 0
        for slot in model.slots {
            for tile in slot.tiles {
                let extent = DockLayout.tileExtent(kind: tile.kind, baseSize: base, edge: anchor.edge).along
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
}
