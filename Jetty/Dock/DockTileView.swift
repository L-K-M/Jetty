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
    /// The edge this dock is anchored to (from the panel's anchor, not the global
    /// preference) so per-display docks with different edges lay out correctly (BUG-4).
    let edge: DockEdge
    /// Whether the clock tile may apply its face zoom. Off in the overflow-scroll
    /// state, where the scroll viewport would clip the oversize face (the same
    /// reason magnification is suspended there).
    var allowsClockZoom: Bool = true

    var onTap: () -> Void
    var onHoverChanged: (Bool) -> Void
    var onDropURLs: ([URL]) -> Void
    var contextActions: () -> [DockContextAction]

    @State private var isDropTargeted = false

    var body: some View {
        visual
            // Reclaim the dead strip between the icon and the screen edge as part of the
            // tap target so a click slammed to the very edge still hits the icon above
            // it (Fitts' law). `DockView` drops its matching edge-side padding, so the
            // dock's overall size is unchanged.
            .padding(edgeInsets)
            .contentShape(Rectangle())
            .onHover { onHoverChanged($0) }
            .onTapGesture(perform: onTap)
            .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
                loadURLs(from: providers)
                return true
            }
            .background(dropHighlight)
            .contextMenu { contextMenuItems }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityLabel)
            .accessibilityValue(tile.isRunning && tile.kind == .application ? "Running" : "")
            .accessibilityAddTraits(tile.kind == .separator ? [] : .isButton)
            // Track the pointer with almost no lag so magnification feels immediate
            // even on fast moves (a long spring made the icon visibly trail the cursor).
            .animation(.interactiveSpring(response: 0.10, dampingFraction: 0.9), value: scale)
            .animation(.easeOut(duration: 0.2), value: isHovered)
    }

    /// The icon (or widget) with its magnification scale, indicator, and label. The
    /// active-app glow is drawn by `DockView` *inside* the clipped glass strip (so it
    /// can't bloom past the dock's edges), not here on the icon.
    private var visual: some View {
        content
            .frame(width: tileWidth, height: baseSize)
            .scaleEffect(scale, anchor: scaleAnchor)
            .overlay(alignment: indicatorAlignment) { indicator }
            .overlay(alignment: .top) { label }
    }

    /// Padding added on the edge-facing side only, turning the gap between the icon and
    /// the screen edge into hittable tap area (Fitts' law).
    private var edgeInsets: EdgeInsets {
        let p = DockView.padding
        switch edge {
        case .bottom: return EdgeInsets(top: 0, leading: 0, bottom: p, trailing: 0)
        case .top:    return EdgeInsets(top: p, leading: 0, bottom: 0, trailing: 0)
        case .left:   return EdgeInsets(top: 0, leading: p, bottom: 0, trailing: 0)
        case .right:  return EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: p)
        }
    }

    /// VoiceOver label per tile kind (BUG-9).
    private var accessibilityLabel: String {
        switch tile.kind {
        case .separator: return "Separator"
        case .clock: return "Clock"
        case .battery: return "Battery"
        case .systemMonitor: return "System monitor"
        case .worldClock: return "World clock"
        case .pomodoro: return "Pomodoro timer"
        case .weather: return "Weather"
        case .nowPlaying: return "Now playing"
        case .jettyMenu: return "Jetty Menu"
        case .trash: return "Trash"
        default: return tile.displayName.isEmpty ? "Dock item" : tile.displayName
        }
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
                .frame(width: edge.isHorizontal ? 1 : baseSize * 0.5,
                       height: edge.isHorizontal ? baseSize * 0.5 : 1)
        case .clock:
            ClockWidgetView(preferences: preferences, height: baseSize, edge: edge,
                            allowsZoom: allowsClockZoom)
        case .battery:
            BatteryWidgetView(height: baseSize, tint: preferences.tintColor)
        case .systemMonitor:
            SystemMonitorWidgetView(height: baseSize, tint: preferences.tintColor,
                                    style: preferences.systemMonitorStyle,
                                    showNetwork: preferences.systemMonitorShowNetwork)
        case .worldClock:
            WorldClockWidgetView(preferences: preferences, height: baseSize)
        case .pomodoro:
            PomodoroWidgetView(height: baseSize, tint: preferences.tintColor)
        case .weather:
            WeatherWidgetView(preferences: preferences, height: baseSize, tint: preferences.tintColor)
        case .nowPlaying:
            NowPlayingWidgetView(height: baseSize, tint: preferences.tintColor)
        case .jettyMenu:
            Image(systemName: JettyMenuGlyph.resolved(preferences.jettyMenuSymbol))
                .resizable().scaledToFit().padding(baseSize * 0.18)
                .foregroundStyle(preferences.glyphColor)
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
                    .frame(width: edge.isHorizontal ? baseSize * 0.4 : 3,
                           height: edge.isHorizontal ? 3 : baseSize * 0.4)
                    .padding(1)
            case .underline:
                RoundedRectangle(cornerRadius: 1).fill(preferences.indicatorColor)
                    .frame(width: edge.isHorizontal ? baseSize * 0.6 : 2,
                           height: edge.isHorizontal ? 2 : baseSize * 0.6)
            case .none:
                EmptyView()
            }
        }
    }

    private var indicatorAlignment: Alignment {
        switch edge {
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
        case .separator: return edge.isHorizontal ? 12 : baseSize
        case .clock where edge.isHorizontal:
            // Widens with a zoomed watch face — keep in sync with
            // `DockLayout.tileExtent` so panel sizing and rendering agree. In the
            // overflow-scroll state the face renders unzoomed (`allowsClockZoom`
            // is false), so the tile keeps its resting width too instead of
            // holding a zoom-wide slab of empty glass around a 1× face.
            return baseSize * DockLayout.clockTileWidthFactor(
                zoom: allowsClockZoom ? CGFloat(preferences.effectiveClockZoom) : 1)
        default: return baseSize * tile.kind.tileWidthFactor
        }
    }

    private var scaleAnchor: UnitPoint {
        switch edge {
        case .bottom: return .bottom
        case .top: return .top
        case .left: return .leading
        case .right: return .trailing
        }
    }

    private func loadURLs(from providers: [NSItemProvider]) {
        var urls: [URL] = []
        let group = DispatchGroup()
        let lock = NSLock()
        for provider in providers {
            group.enter()
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                if let url {
                    lock.lock()
                    urls.append(url)
                    lock.unlock()
                }
                group.leave()
            }
        }
        group.notify(queue: .main) {
            if !urls.isEmpty { onDropURLs(urls) }
        }
    }
}
