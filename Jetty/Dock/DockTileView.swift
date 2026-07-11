import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// A single dock tile: app/file icon (or a built-in widget), a running indicator,
/// an optional hover label, magnification scaling, and a file-drop target. Pointer
/// state is reported up to `DockView`, which drives the magnification curve.
struct DockTileView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let tile: DockTile
    @ObservedObject var preferences: Preferences
    let baseSize: CGFloat
    let scale: CGFloat
    let isHovered: Bool
    let isUnresponsive: Bool
    /// The edge this dock is anchored to (from the panel's anchor, not the global
    /// preference) so per-display docks with different edges lay out correctly (BUG-4).
    let edge: DockEdge
    /// Whether the clock tile may apply its face zoom. Off in the overflow-scroll
    /// state, where the scroll viewport would clip the oversize face (the same
    /// reason magnification is suspended there).
    var allowsClockZoom: Bool = true
    /// Whether this tile has its own file-drop action (app opens files, Trash deletes).
    /// Other tiles still let the dock background pin drops, but don't show as targets.
    var acceptsFileDrop: Bool = false

    var onTap: () -> Void
    var onHoverChanged: (Bool) -> Void
    var onDropURLs: ([URL]) -> Void
    var contextActions: () -> [DockContextAction]
    var onContextMenuPresentationChanged: (Bool) -> Void

    @State private var isDropTargeted = false
    @State private var isPrimaryPressed = false
    @State private var actionPulse = false
    @State private var dropAcceptedPulse = false

    var body: some View {
        visual
            // Reclaim the dead strip between the icon and the screen edge as part of the
            // tap target so a click slammed to the very edge still hits the icon above
            // it (Fitts' law). `DockView` drops its matching edge-side padding, so the
            // dock's overall size is unchanged.
            .padding(edgeInsets)
            .contentShape(Rectangle())
            .onHover { onHoverChanged($0) }
            .onTapGesture {
                pulseAction()
                onTap()
            }
            .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
                loadURLs(from: providers)
                return true
            }
            .overlay { dropHighlight }
            .overlay { actionHighlight }
            .overlay {
                DockContextMenuSource(
                    edge: edge,
                    dockThickness: baseSize + 2 * DockView.padding,
                    actions: contextActions,
                    onPresentationChanged: onContextMenuPresentationChanged,
                    onPrimaryPressChanged: { pressed in
                        isPrimaryPressed = isActionable && pressed
                    })
                    .accessibilityHidden(true)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityLabel)
            .accessibilityValue(accessibilityValue)
            .accessibilityAddTraits(tile.kind == .separator ? [] : .isButton)
            .accessibilityActions {
                ForEach(contextActions().filter { !$0.isSeparator }) { action in
                    Button(role: action.isDestructive ? .destructive : nil) {
                        action.action?()
                    } label: {
                        Text(action.title)
                    }
                }
            }
            .help(isUnresponsive ? "\(tile.displayName) - Not Responding" : tile.displayName)
            // Track the pointer with almost no lag so magnification feels immediate
            // even on fast moves (a long spring made the icon visibly trail the cursor).
            .animation(.interactiveSpring(response: 0.10, dampingFraction: 0.9), value: scale)
            .animation(.easeOut(duration: 0.2), value: isHovered)
            .animation(reduceMotion ? nil : .spring(response: 0.2, dampingFraction: 0.65),
                       value: actionPulse)
            .animation(reduceMotion ? nil : .spring(response: 0.25, dampingFraction: 0.55),
                       value: dropAcceptedPulse)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: isDropTargeted)
    }

    /// The icon (or widget) with its magnification scale, indicator, and label. The
    /// active-app glow is drawn by `DockView` *inside* the clipped glass strip (so it
    /// can't bloom past the dock's edges), not here on the icon.
    private var visual: some View {
        content
            .frame(width: tileWidth, height: baseSize)
            .scaleEffect(scale, anchor: scaleAnchor)
            .scaleEffect(isPrimaryPressed && !reduceMotion ? 0.94 : 1,
                         anchor: scaleAnchor)
            .brightness(isPrimaryPressed ? -0.10 : 0)
            .overlay { pressedHighlight }
            .overlay(alignment: .topTrailing) { unresponsiveBadge }
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

    private var accessibilityValue: String {
        guard tile.kind == .application, tile.isRunning else { return "" }
        return isUnresponsive ? "Running, Not Responding" : "Running"
    }

    private var isActionable: Bool {
        tile.kind != .separator && tile.kind != .runningApps
    }

    @ViewBuilder
    private var pressedHighlight: some View {
        if isPrimaryPressed {
            RoundedRectangle(cornerRadius: max(8, baseSize * 0.20), style: .continuous)
                .fill(Color.black.opacity(0.14))
                .overlay {
                    RoundedRectangle(cornerRadius: max(8, baseSize * 0.20), style: .continuous)
                        .stroke(Color.white.opacity(0.34), lineWidth: 1)
                }
                .padding(1)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private var unresponsiveBadge: some View {
        if tile.kind == .application && isUnresponsive {
            Image(systemName: "exclamationmark.circle.fill")
                .symbolRenderingMode(.palette)
                .foregroundStyle(.white, .red)
                .font(.system(size: max(12, baseSize * 0.28), weight: .bold))
                .offset(x: 2, y: -2)
                .help("Not Responding")
                .accessibilityHidden(true)
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
        if isDropTargeted && acceptsFileDrop {
            if tile.kind == .trash {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.red.opacity(0.24))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.red, lineWidth: 3)
                    }
                    .overlay(alignment: .bottomTrailing) {
                        Image(systemName: "arrow.down")
                            .font(.system(size: max(10, baseSize * 0.22), weight: .bold))
                            .foregroundStyle(.white)
                            .padding(max(4, baseSize * 0.08))
                            .background(Color.red, in: Circle())
                            .overlay(Circle().stroke(.white.opacity(0.9), lineWidth: 1))
                            .padding(2)
                    }
                    .shadow(color: .red.opacity(0.45), radius: 8)
                    .allowsHitTesting(false)
            } else {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(preferences.tintColor.opacity(0.18))
                    .overlay {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(preferences.tintColor, lineWidth: 2)
                    }
                    .allowsHitTesting(false)
            }
        }
    }

    @ViewBuilder
    private var actionHighlight: some View {
        if tile.kind == .trash, actionPulse || dropAcceptedPulse {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(dropAcceptedPulse ? Color.red : preferences.tintColor,
                        lineWidth: dropAcceptedPulse ? 4 : 2)
                .padding(3)
                .opacity(reduceMotion ? 1 : 0.9)
                .allowsHitTesting(false)
        }
    }

    private func pulseAction() {
        guard tile.kind == .trash else { return }
        actionPulse = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { actionPulse = false }
    }

    private func pulseDropAccepted() {
        guard tile.kind == .trash else { return }
        dropAcceptedPulse = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) { dropAcceptedPulse = false }
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
                zoom: allowsClockZoom ? CGFloat(preferences.effectiveClockZoom) : 1,
                face: preferences.clockFace)
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
            if !urls.isEmpty {
                onDropURLs(urls)
                pulseDropAccepted()
            }
        }
    }
}
