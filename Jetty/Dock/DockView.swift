import SwiftUI

/// The dock's SwiftUI content: a row (or column) of tiles on a Liquid Glass slab,
/// with Dock-style hover magnification. Sizing is driven by the panel (via
/// `DockLayout`); this view just lays the tiles against the edge so they magnify
/// inward. See PLAN.md §4, §9.
struct DockView: View {
    @ObservedObject var model: DockModel
    @ObservedObject var preferences: Preferences

    @State private var hoveredIndex: Int?

    /// Shared inner padding — also used by `DockLayout.contentSize` so the window
    /// frame and the SwiftUI content agree.
    static let padding: CGFloat = 10

    var body: some View {
        let edge = preferences.edge
        let base = CGFloat(preferences.iconSize)
        let spacing = CGFloat(preferences.tileSpacing)

        tileStack(edge: edge, base: base, spacing: spacing)
            .padding(Self.padding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: edgeAlignment(edge))
            .background(
                GlassBackground(material: preferences.material,
                                tint: preferences.tintColor,
                                gradientColor: preferences.gradientColor,
                                gradientAngle: preferences.gradientAngle,
                                opacity: preferences.backgroundOpacity,
                                cornerRadius: CGFloat(preferences.cornerRadius))
            )
            .onHover { inside in if !inside { hoveredIndex = nil } }
    }

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
            contextActions: { model.onRequestContextActions?(tile) ?? [] }
        )
    }

    /// Magnification factor for the tile at `index`, based on its distance (in tiles)
    /// from the hovered tile.
    private func scale(for index: Int, base: CGFloat, spacing: CGFloat) -> CGFloat {
        guard preferences.magnificationEnabled, let hovered = hoveredIndex else { return 1 }
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
