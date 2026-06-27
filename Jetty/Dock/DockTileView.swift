import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// A single dock tile: app/file icon (or a built-in widget), a running indicator,
/// an optional hover label, magnification scaling, and a file-drop target. Pointer
/// state is reported up to `DockView`, which drives the magnification curve.
struct DockTileView: View {
    let tile: DockTile
    @ObservedObject var preferences: Preferences
    let baseSize: CGFloat
    let scale: CGFloat
    let isHovered: Bool

    var onTap: () -> Void
    var onHoverChanged: (Bool) -> Void
    var onDropURLs: ([URL]) -> Void
    var contextActions: () -> [DockContextAction]
    var dragOffset: CGSize
    var isDragging: Bool
    var onReorderChanged: (CGSize) -> Void
    var onReorderEnded: (CGSize) -> Void

    @State private var isDropTargeted = false

    var body: some View {
        content
            .frame(width: tileWidth, height: baseSize)
            .scaleEffect(scale, anchor: scaleAnchor)
            .overlay(alignment: indicatorAlignment) { indicator }
            .overlay(alignment: .top) { label }
            .contentShape(Rectangle())
            .offset(dragOffset)
            .zIndex(isDragging ? 1 : 0)
            .onHover { onHoverChanged($0) }
            .onTapGesture(perform: onTap)
            .gesture(
                DragGesture(minimumDistance: 8)
                    .onChanged { onReorderChanged($0.translation) }
                    .onEnded { onReorderEnded($0.translation) }
            )
            .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
                loadURLs(from: providers)
                return true
            }
            .background(dropHighlight)
            .contextMenu { contextMenuItems }
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: scale)
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isDragging)
    }

    @ViewBuilder
    private var contextMenuItems: some View {
        let actions = contextActions()
        ForEach(actions) { action in
            if action.isSeparator {
                Divider()
            } else {
                Button(role: action.isDestructive ? .destructive : nil) {
                    action.action?()
                } label: {
                    Text(action.title)
                }
            }
        }
    }

    // MARK: Content per kind

    @ViewBuilder
    private var content: some View {
        switch tile.kind {
        case .separator:
            Rectangle()
                .fill(Color.primary.opacity(0.18))
                .frame(width: preferences.edge.isHorizontal ? 1 : baseSize * 0.5,
                       height: preferences.edge.isHorizontal ? baseSize * 0.5 : 1)
        case .clock:
            ClockWidgetView(preferences: preferences, height: baseSize)
        case .jettyMenu:
            Image(systemName: "square.grid.2x2.fill")
                .resizable().scaledToFit().padding(baseSize * 0.18)
                .foregroundStyle(preferences.tintColor)
        default:
            iconImage
        }
    }

    @ViewBuilder
    private var iconImage: some View {
        if let icon = tile.icon {
            Image(nsImage: icon).resizable().scaledToFit().padding(2)
        } else {
            Image(systemName: fallbackSymbol).resizable().scaledToFit()
                .padding(baseSize * 0.2).foregroundStyle(.secondary)
        }
    }

    private var fallbackSymbol: String {
        switch tile.kind {
        case .trash: return "trash"
        case .folder: return "folder.fill"
        case .url: return "globe"
        case .file: return "doc.fill"
        default: return "app.dashed"
        }
    }

    // MARK: Running indicator

    @ViewBuilder
    private var indicator: some View {
        if tile.isRunning && tile.kind == .application {
            switch preferences.indicatorStyle {
            case .dot:
                Circle().fill(preferences.indicatorColor)
                    .frame(width: 4, height: 4).padding(2)
            case .bar:
                RoundedRectangle(cornerRadius: 1).fill(preferences.indicatorColor)
                    .frame(width: preferences.edge.isHorizontal ? baseSize * 0.4 : 3,
                           height: preferences.edge.isHorizontal ? 3 : baseSize * 0.4)
                    .padding(1)
            case .underline:
                RoundedRectangle(cornerRadius: 1).fill(preferences.indicatorColor)
                    .frame(width: preferences.edge.isHorizontal ? baseSize * 0.6 : 2,
                           height: preferences.edge.isHorizontal ? 2 : baseSize * 0.6)
            case .none:
                EmptyView()
            }
        }
    }

    private var indicatorAlignment: Alignment {
        switch preferences.edge {
        case .bottom: return .bottom
        case .top: return .top
        case .left: return .leading
        case .right: return .trailing
        }
    }

    // MARK: Hover label

    @ViewBuilder
    private var label: some View {
        if isHovered && preferences.showLabels && !tile.displayName.isEmpty
            && tile.kind != .separator && tile.kind != .clock {
            Text(tile.displayName)
                .font(.caption2)
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(.thinMaterial, in: Capsule())
                .fixedSize()
                .offset(y: -baseSize * 0.75)
                .allowsHitTesting(false)
        }
    }

    @ViewBuilder
    private var dropHighlight: some View {
        if isDropTargeted {
            RoundedRectangle(cornerRadius: 8).stroke(preferences.tintColor, lineWidth: 2)
        }
    }

    // MARK: Geometry

    private var tileWidth: CGFloat {
        switch tile.kind {
        case .separator: return preferences.edge.isHorizontal ? 12 : baseSize
        case .clock: return baseSize * 1.6
        default: return baseSize
        }
    }

    private var scaleAnchor: UnitPoint {
        switch preferences.edge {
        case .bottom: return .bottom
        case .top: return .top
        case .left: return .leading
        case .right: return .trailing
        }
    }

    private func loadURLs(from providers: [NSItemProvider]) {
        var urls: [URL] = []
        let group = DispatchGroup()
        for provider in providers {
            group.enter()
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                if let url { urls.append(url) }
                group.leave()
            }
        }
        group.notify(queue: .main) {
            if !urls.isEmpty { onDropURLs(urls) }
        }
    }
}
