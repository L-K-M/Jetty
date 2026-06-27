import SwiftUI
import AppKit

/// The dock's SwiftUI content: a row (or column) of **slots** on a Liquid Glass
/// strip, with Dock-style hover magnification and live drag-to-reorder. Running
/// apps collapse into one slot so they move as a unit and pinned items can sit on
/// either side of them. The glass is a resting-height strip hugging the edge; tiles
/// magnify into transparent headroom above it. See PLAN.md §4, §7, §9.
struct DockView: View {
    @ObservedObject var model: DockModel
    @ObservedObject var preferences: Preferences

    @State private var hoveredTileID: String?
    @State private var draggingSlotID: String?
    @State private var dragAlong: CGFloat = 0
    @State private var dragCross: CGFloat = 0

    /// Shared inner padding — also used by `DockLayout.contentSize` so the window
    /// frame and the SwiftUI content agree.
    static let padding: CGFloat = 10

    var body: some View {
        let edge = preferences.edge
        let base = CGFloat(preferences.iconSize)
        let spacing = CGFloat(preferences.tileSpacing)
        let resting = base + 2 * Self.padding

        ZStack(alignment: edgeAlignment(edge)) {
            glassStrip(edge: edge, thickness: resting)
            slotStack(edge: edge, base: base, spacing: spacing)
                .padding(Self.padding)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: edgeAlignment(edge))
        .onHover { inside in if !inside { hoveredTileID = nil } }
    }

    // MARK: Glass strip

    @ViewBuilder
    private func glassStrip(edge: DockEdge, thickness: CGFloat) -> some View {
        let bg = GlassBackground(material: preferences.material,
                                 tint: preferences.tintColor,
                                 gradientColor: preferences.gradientColor,
                                 gradientAngle: preferences.gradientAngle,
                                 opacity: preferences.backgroundOpacity,
                                 cornerRadius: CGFloat(preferences.cornerRadius))
        if edge.isHorizontal {
            bg.frame(maxWidth: .infinity).frame(height: thickness)
        } else {
            bg.frame(maxHeight: .infinity).frame(width: thickness)
        }
    }

    // MARK: Slots

    @ViewBuilder
    private func slotStack(edge: DockEdge, base: CGFloat, spacing: CGFloat) -> some View {
        let flat = flatIndices()
        let slots = Array(model.slots.enumerated())
        if edge.isHorizontal {
            HStack(spacing: spacing) {
                ForEach(slots, id: \.element.id) { index, slot in
                    slotView(slot, slotIndex: index, base: base, spacing: spacing, flat: flat)
                }
            }
        } else {
            VStack(spacing: spacing) {
                ForEach(slots, id: \.element.id) { index, slot in
                    slotView(slot, slotIndex: index, base: base, spacing: spacing, flat: flat)
                }
            }
        }
    }

    private func slotView(_ slot: DockSlot, slotIndex: Int, base: CGFloat, spacing: CGFloat,
                          flat: [String: Int]) -> some View {
        let isDragged = draggingSlotID == slot.id
        let offset = slotOffset(for: slotIndex, base: base, spacing: spacing)

        return slotTiles(slot, base: base, spacing: spacing, flat: flat)
            .offset(offset)
            .zIndex(isDragged ? 1 : 0)
            .animation(isDragged ? nil : .spring(response: 0.26, dampingFraction: 0.85), value: offset)
            // Gate the reorder drag without passing a nil gesture: `.subviews` keeps
            // child taps (launching a running app) working while disabling the slot drag.
            .gesture(reorderGesture(for: slot), including: slot.isReorderable ? .all : .subviews)
    }

    @ViewBuilder
    private func slotTiles(_ slot: DockSlot, base: CGFloat, spacing: CGFloat, flat: [String: Int]) -> some View {
        let edge = preferences.edge
        if slot.tiles.count <= 1, let tile = slot.tiles.first {
            tileView(tile, flatIndex: flat[tile.id] ?? 0, base: base)
        } else if edge.isHorizontal {
            HStack(spacing: spacing) {
                ForEach(slot.tiles) { tile in tileView(tile, flatIndex: flat[tile.id] ?? 0, base: base) }
            }
        } else {
            VStack(spacing: spacing) {
                ForEach(slot.tiles) { tile in tileView(tile, flatIndex: flat[tile.id] ?? 0, base: base) }
            }
        }
    }

    private func tileView(_ tile: DockTile, flatIndex: Int, base: CGFloat) -> some View {
        DockTileView(
            tile: tile,
            preferences: preferences,
            baseSize: base,
            scale: scale(forFlatIndex: flatIndex, base: base),
            isHovered: hoveredTileID == tile.id,
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
                dragAlong = preferences.edge.isHorizontal ? value.translation.width : value.translation.height
                dragCross = preferences.edge.isHorizontal ? value.translation.height : value.translation.width
            }
            .onEnded { _ in
                commitReorder()
                draggingSlotID = nil
                dragAlong = 0
                dragCross = 0
            }
    }

    /// The on-screen offset for the slot at `index`: the dragged slot follows the
    /// pointer; the others slide to open a gap at the live target position.
    private func slotOffset(for index: Int, base: CGFloat, spacing: CGFloat) -> CGSize {
        guard let draggingSlotID,
              let dragged = model.slots.firstIndex(where: { $0.id == draggingSlotID }) else { return .zero }
        let edge = preferences.edge
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
                                       spacing: spacing, edge: preferences.edge)
        }
    }

    // MARK: Magnification

    private func scale(forFlatIndex index: Int, base: CGFloat) -> CGFloat {
        guard preferences.magnificationEnabled, draggingSlotID == nil,
              let hoveredID = hoveredTileID,
              let hovered = flatIndices()[hoveredID] else { return 1 }
        let step = base + CGFloat(preferences.tileSpacing)
        let distance = CGFloat(abs(index - hovered)) * step
        return MagnificationCurve.scale(distance: distance, influence: step * 2.2,
                                        maxScale: preferences.effectiveMagnification)
    }

    // MARK: Helpers

    /// Flat 0-based index of each tile across all slots, for magnification distance.
    private func flatIndices() -> [String: Int] {
        var map: [String: Int] = [:]
        var k = 0
        for slot in model.slots {
            for tile in slot.tiles { map[tile.id] = k; k += 1 }
        }
        return map
    }

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
