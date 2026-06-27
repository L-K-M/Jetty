import SwiftUI
import AppKit

/// The dock's SwiftUI content: a row (or column) of tiles on a Liquid Glass slab,
/// with Dock-style hover magnification and drag-to-reorder.
///
/// The glass is a **resting-height strip hugging the chosen edge**; the window is
/// taller than that strip by the magnification headroom, which stays transparent so
/// hovered tiles grow *into* it instead of the slab itself being tall (which would
/// leave a gap above un-magnified icons). See PLAN.md §4, §9.
struct DockView: View {
    @ObservedObject var model: DockModel
    @ObservedObject var preferences: Preferences

    @State private var hoveredIndex: Int?
    @State private var draggingID: String?
    @State private var dragTranslation: CGSize = .zero

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
            tileStack(edge: edge, base: base, spacing: spacing)
                .padding(Self.padding)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: edgeAlignment(edge))
        .onHover { inside in if !inside { hoveredIndex = nil } }
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

    // MARK: Tiles

    @ViewBuilder
    private func tileStack(edge: DockEdge, base: CGFloat, spacing: CGFloat) -> some View {
        let tiles = Array(model.tiles.enumerated())
        if edge.isHorizontal {
            HStack(spacing: spacing) {
                ForEach(tiles, id: \.element.id) { index, tile in
                    tileView(tile, index: index, base: base, spacing: spacing)
                }
            }
        } else {
            VStack(spacing: spacing) {
                ForEach(tiles, id: \.element.id) { index, tile in
                    tileView(tile, index: index, base: base, spacing: spacing)
                }
            }
        }
    }

    private func tileView(_ tile: DockTile, index: Int, base: CGFloat, spacing: CGFloat) -> some View {
        DockTileView(
            tile: tile,
            preferences: preferences,
            baseSize: base,
            scale: scale(for: index, base: base, spacing: spacing),
            isHovered: hoveredIndex == index,
            onTap: { model.onOpenTile?(tile) },
            onHoverChanged: { inside in hoveredIndex = inside ? index : (hoveredIndex == index ? nil : hoveredIndex) },
            onDropURLs: { urls in model.onDropFiles?(tile, urls) },
            contextActions: { model.onRequestContextActions?(tile) ?? [] },
            dragOffset: draggingID == tile.id ? dragTranslation : .zero,
            isDragging: draggingID == tile.id,
            onReorderChanged: { translation in
                guard tile.itemID != nil else { return }   // only pinned tiles reorder
                draggingID = tile.id
                dragTranslation = translation
            },
            onReorderEnded: { translation in
                commitReorder(tile: tile, translation: translation)
                draggingID = nil
                dragTranslation = .zero
            }
        )
    }

    // MARK: Drag-to-reorder

    private func commitReorder(tile: DockTile, translation: CGSize) {
        guard let itemID = tile.itemID,
              let currentIndex = model.tiles.firstIndex(where: { $0.id == tile.id }) else { return }
        let step = CGFloat(preferences.iconSize) + CGFloat(preferences.tileSpacing)
        let primary = preferences.edge.isHorizontal ? translation.width : translation.height
        let target = DockLayout.reorderTargetIndex(currentIndex: currentIndex,
                                                   translationPrimary: primary,
                                                   step: step,
                                                   pinnedCount: model.pinnedCount)
        guard target != currentIndex else { return }
        model.onReorder?(itemID, target)
    }

    // MARK: Magnification

    /// Magnification factor for the tile at `index`, based on its distance (in tiles)
    /// from the hovered tile.
    private func scale(for index: Int, base: CGFloat, spacing: CGFloat) -> CGFloat {
        guard preferences.magnificationEnabled, draggingID == nil, let hovered = hoveredIndex else { return 1 }
        let step = base + spacing
        let distance = CGFloat(abs(index - hovered)) * step
        return MagnificationCurve.scale(distance: distance,
                                        influence: step * 2.2,
                                        maxScale: preferences.effectiveMagnification)
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
