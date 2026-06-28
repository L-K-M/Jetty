import SwiftUI
import CoreGraphics

/// Observable backing for the window-peek popover: lists an app's windows and captures
/// their thumbnails off the main thread, refreshing on a timer so the previews stay
/// "live" while the popover is open (ISSUE/MF window management).
final class WindowPeekModel: ObservableObject {
    @Published private(set) var windows: [AppWindow] = []
    @Published private(set) var thumbnails: [CGWindowID: CGImage] = [:]
    @Published private(set) var appName = ""
    /// True when Screen Recording is granted, so the UI can hint when previews are off.
    @Published private(set) var canCapture = CGPreflightScreenCaptureAccess()

    private(set) var pid: pid_t = 0
    private var timer: Timer?
    private var isRefreshing = false

    func load(pid: pid_t, appName: String) {
        timer?.invalidate()
        self.pid = pid
        self.appName = appName
        canCapture = CGPreflightScreenCaptureAccess()
        // Show the window list right away (glyphs); the async capture fills thumbnails in.
        windows = WindowLister.windows(forPID: pid)
        thumbnails = [:]
        refresh()
        let t = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in self?.refresh() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stop() {
        timer?.invalidate(); timer = nil
        windows = []
        thumbnails = [:]
        pid = 0
    }

    private func refresh() {
        let pid = self.pid
        guard pid != 0, !isRefreshing else { return }   // skip if a capture is still in flight
        isRefreshing = true
        Task { [weak self] in
            let wins = WindowLister.windows(forPID: pid)
            let thumbs = await WindowThumbnailer.images(for: wins)
            await MainActor.run {
                guard let self else { return }
                self.isRefreshing = false
                guard self.pid == pid else { return }   // ignore stale loads
                self.windows = wins
                self.thumbnails = thumbs
            }
        }
    }
}

/// The window-peek popover: a row of live window thumbnails for one app. Clicking a
/// thumbnail raises that window; the corner button minimizes it. Degrades to a window
/// glyph + a Screen-Recording hint when previews aren't permitted.
struct WindowPeekView: View {
    @ObservedObject var model: WindowPeekModel
    @ObservedObject var preferences: Preferences
    var onSelect: (AppWindow) -> Void
    var onMinimize: (AppWindow) -> Void
    var onHoverChange: (Bool) -> Void

    private let thumbHeight: CGFloat = 116

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(model.appName).font(.headline).lineLimit(1)
                Spacer()
                Text("\(model.windows.count) window\(model.windows.count == 1 ? "" : "s")")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if model.windows.isEmpty {
                Text("No open windows")
                    .font(.callout).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: thumbHeight)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(model.windows) { window in thumbnail(window) }
                    }
                }
            }
            if !model.canCapture {
                Label("Enable Screen Recording in Settings → Permissions for live previews.",
                      systemImage: "info.circle")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            GlassBackground(material: preferences.material,
                            tint: preferences.tintColor,
                            gradientColor: preferences.gradientColor,
                            gradientAngle: preferences.gradientAngle,
                            opacity: max(preferences.backgroundOpacity, 0.85),
                            cornerRadius: 16)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .onHover { onHoverChange($0) }
    }

    private func thumbnail(_ window: AppWindow) -> some View {
        let aspect = window.bounds.height > 0 ? window.bounds.width / window.bounds.height : 1.6
        let width = min(max(thumbHeight * aspect, 80), 260)
        return VStack(spacing: 4) {
            Button { onSelect(window) } label: {
                ZStack(alignment: .topTrailing) {
                    preview(window)
                        .frame(width: width, height: thumbHeight)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Color.primary.opacity(0.12), lineWidth: 1))
                    Button { onMinimize(window) } label: {
                        Image(systemName: "minus.circle.fill")
                            .font(.system(size: 16))
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, .black.opacity(0.45))
                    }
                    .buttonStyle(.plain)
                    .padding(5)
                    .help("Minimize")
                }
            }
            .buttonStyle(.plain)
            Text(window.title.isEmpty ? model.appName : window.title)
                .font(.caption2).foregroundStyle(.secondary)
                .lineLimit(1).truncationMode(.middle)
                .frame(width: width)
        }
    }

    @ViewBuilder
    private func preview(_ window: AppWindow) -> some View {
        if let cg = model.thumbnails[window.id] {
            Image(decorative: cg, scale: 1)
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else {
            ZStack {
                Color.primary.opacity(0.08)
                Image(systemName: "macwindow")
                    .font(.system(size: 30)).foregroundStyle(.secondary)
            }
        }
    }
}
