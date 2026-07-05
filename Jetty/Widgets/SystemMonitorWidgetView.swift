import SwiftUI
import AppKit

/// A CPU + memory tile (ND-3), fed by the shared `LiveSystemStats` sampler (one read
/// per tick across all displays — ISSUE-5). Two presentations:
/// - `.bars`: two slim gauges (load + memory pressure), the original compact look.
/// - `.graph`: a time-series sparkline of CPU and memory over the last ~2 minutes,
///   plus an optional network-throughput trace, drawn on a dark glassy plate so the
///   series read against a constant background instead of the dock glass.
struct SystemMonitorWidgetView: View {
    var height: CGFloat
    var tint: Color
    var style: SystemMonitorStyle = .bars
    var showNetwork: Bool = false
    @ObservedObject private var stats = LiveSystemStats.shared

    /// Fixed series colors (so they stay distinct from each other and the tint).
    private let ramColor = Color.orange
    private let netColor = Color.teal

    var body: some View {
        Group {
            switch style {
            case .bars:  barsBody
            case .graph: graphBody
            case .scope: scopeBody
            case .led:   SystemMonitorLEDView(cpu: stats.load, ram: stats.memory, height: height)
            case .gauges: SystemMonitorGaugeView(cpu: stats.load, ram: stats.memory, height: height)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .help(helpText)
    }

    private var scopeBody: some View {
        let samples = stats.history
        return SystemMonitorScopeView(
            cpu: samples.map(\.load),
            ram: samples.map(\.memory),
            net: showNetwork
                ? SystemMonitorGraph.autoScaled(samples.map { $0.netDown + $0.netUp },
                                                floor: SystemMonitorGraph.netFloor)
                : [],
            cpuValue: stats.load,
            ramValue: stats.memory,
            netRate: currentNetRate,
            showNetwork: showNetwork,
            height: height)
    }

    private var helpText: String {
        switch style {
        case .led, .gauges:
            // These looks show no numerals at all, so the tooltip carries the
            // live values (FAB-A2). Recomputed on every published sample.
            var text = "CPU \(percent(stats.load))% · RAM \(percent(stats.memory))%"
            if showNetwork && style.supportsNetwork {
                text += " · Net \(SystemMonitorGraph.formatRate(currentNetRate))"
            }
            return text
        default:
            return style.supportsNetwork
                ? "CPU, memory\(showNetwork ? ", and network" : "") over the last couple of minutes"
                : "CPU load and memory usage"
        }
    }

    // MARK: Bars

    private var barsBody: some View {
        HStack(spacing: 6) {
            meter(label: "CPU", value: stats.load)
            meter(label: "RAM", value: stats.memory)
        }
        .padding(.horizontal, 6)
    }

    private func meter(label: String, value: Double) -> some View {
        let clamped = min(max(value, 0), 1)
        let color = barColor(clamped)
        // The numeral gets the same readability lift the graph legend got
        // (FAB-V5): below 60% load `barColor` is the raw tint, which can be
        // near-black on the dock glass. The bar fill itself keeps the exact
        // tint — the capsule reads by shape and glow, not contrast.
        let textColor = readableColor(color)
        return VStack(spacing: 3) {
            Text(label)
                .font(.system(size: max(7, height * 0.15), weight: .bold, design: .rounded))
                .foregroundStyle(.secondary)
                .tracking(0.5)
            GeometryReader { geo in
                ZStack(alignment: .bottom) {
                    Capsule(style: .continuous).fill(Color.primary.opacity(0.12))
                    Capsule(style: .continuous)
                        .fill(LinearGradient(colors: [color.opacity(0.6), color],
                                             startPoint: .bottom, endPoint: .top))
                        .frame(height: max(3, geo.size.height * clamped))
                        .shadow(color: color.opacity(0.5), radius: 2, y: -1)
                }
            }
            .frame(width: max(7, height * 0.2))
            Text("\(Int((clamped * 100).rounded()))")
                .font(.system(size: max(8, height * 0.18), weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(textColor)
        }
    }

    private func barColor(_ value: Double) -> Color {
        switch value {
        case ..<0.6: return tint
        case ..<0.85: return .orange
        default: return .red
        }
    }

    // MARK: Graph

    private var graphBody: some View {
        let samples = stats.history
        let cpu = samples.map(\.load)
        let ram = samples.map(\.memory)
        let net = showNetwork
            ? SystemMonitorGraph.autoScaled(samples.map { $0.netDown + $0.netUp },
                                            floor: SystemMonitorGraph.netFloor)
            : []
        let cpuColor = readableCPUColor
        let labelSize = max(7, height * 0.15)
        // Legend sits in its own row ABOVE the chart so the sparklines never draw over
        // the numbers; the chart fills the space that remains.
        return VStack(spacing: 2) {
            HStack(spacing: 6) {
                legendValue("\(percent(stats.load))", color: cpuColor)
                legendValue("\(percent(stats.memory))", color: ramColor)
                if showNetwork {
                    legendValue(SystemMonitorGraph.formatRate(currentNetRate), color: netColor)
                }
                Spacer(minLength: 0)
            }
            .font(.system(size: labelSize, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .fixedSize(horizontal: false, vertical: true)

            chart(cpu: cpu, ram: ram, net: net, cpuColor: cpuColor)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        // The plate: the sparklines used to float straight on the dock glass —
        // unreadable over busy content, and worse when the magnified tile pokes
        // past the strip onto transparency. A dark glassy card (same treatment
        // as the classic clock dial and the LCD screen) gives the series and
        // legend a constant background to read against, in any tint or theme.
        .background(plate)
        .padding(2)
    }

    private var plate: some View {
        let shape = RoundedRectangle(cornerRadius: height * 0.16, style: .continuous)
        return shape.fill(Color.black.opacity(0.32))
            .overlay(shape.fill(LinearGradient(colors: [.white.opacity(0.08), .clear],
                                               startPoint: .top, endPoint: .bottom)))
            .overlay(shape.stroke(.white.opacity(0.16), lineWidth: 1))
    }

    private func chart(cpu: [Double], ram: [Double], net: [Double], cpuColor: Color) -> some View {
        GeometryReader { geo in
            let size = geo.size
            // Faint quarter gridlines so levels read against something; the
            // midline slightly stronger.
            gridline(at: 0.5, in: size).stroke(.white.opacity(0.14), lineWidth: 0.5)
            gridline(at: 0.25, in: size).stroke(.white.opacity(0.07), lineWidth: 0.5)
            gridline(at: 0.75, in: size).stroke(.white.opacity(0.07), lineWidth: 0.5)
            // CPU: filled area + line (the dominant series, in the readable tint).
            SystemMonitorGraph.areaPath(cpu, in: size)
                .fill(LinearGradient(colors: [cpuColor.opacity(0.40), cpuColor.opacity(0.03)],
                                     startPoint: .top, endPoint: .bottom))
            SystemMonitorGraph.linePath(cpu, in: size)
                .stroke(cpuColor, style: StrokeStyle(lineWidth: 1.5, lineJoin: .round))
            // RAM: line only.
            SystemMonitorGraph.linePath(ram, in: size)
                .stroke(ramColor, style: StrokeStyle(lineWidth: 1.5, lineJoin: .round))
            // Network: thin auto-scaled line.
            if showNetwork {
                SystemMonitorGraph.linePath(net, in: size)
                    .stroke(netColor.opacity(0.9), style: StrokeStyle(lineWidth: 1, lineJoin: .round))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
    }

    private func gridline(at fraction: CGFloat, in size: CGSize) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 0, y: size.height * fraction))
        path.addLine(to: CGPoint(x: size.width, y: size.height * fraction))
        return path
    }

    /// The CPU series color: the user's tint, lifted toward white when it's too
    /// dark to read on the dark plate (perceived luminance, like the menu's
    /// selected-row text — M10).
    private var readableCPUColor: Color { readableColor(tint) }

    /// `color`, lifted toward white when it's too dark to read as text
    /// (perceived luminance + `SystemMonitorGraph.whiteLift`). Used everywhere
    /// a series color feeds text/legend rendering; bright colors pass through
    /// untouched.
    private func readableColor(_ color: Color) -> Color {
        guard let rgb = NSColor(color).usingColorSpace(.sRGB) else { return color }
        let luminance = 0.299 * rgb.redComponent + 0.587 * rgb.greenComponent + 0.114 * rgb.blueComponent
        let lift = SystemMonitorGraph.whiteLift(forLuminance: luminance)
        guard lift > 0, let lifted = rgb.blended(withFraction: lift, of: .white) else { return color }
        return Color(nsColor: lifted)
    }

    /// A colored dot plus a white number: the number stays readable no matter
    /// how dark the series color is; the dot maps it to its line.
    private func legendValue(_ text: String, color: Color) -> some View {
        HStack(spacing: 2.5) {
            Circle()
                .fill(color)
                .frame(width: 5, height: 5)
                .overlay(Circle().stroke(.white.opacity(0.25), lineWidth: 0.5))
            Text(text)
                .foregroundStyle(.white.opacity(0.92))
                .lineLimit(1)
                .minimumScaleFactor(0.5)
        }
    }

    private func percent(_ value: Double) -> Int { Int((min(max(value, 0), 1) * 100).rounded()) }

    private var currentNetRate: Double {
        guard let last = stats.history.last else { return 0 }
        return last.netDown + last.netUp
    }
}

/// Pure geometry/formatting for the System Monitor graph, split out so it's unit-tested
/// without SwiftUI.
enum SystemMonitorGraph {
    /// Idle-network floor (bytes/s) for auto-scaling, so a quiet link reads as a low flat
    /// line instead of amplifying byte-level noise to full height.
    static let netFloor: Double = 64 * 1024

    /// Scales `values` to 0…1 against the larger of their own max and `floor`.
    static func autoScaled(_ values: [Double], floor: Double) -> [Double] {
        let maxV = Swift.max(values.max() ?? 0, Swift.max(floor, 0.000001))
        return values.map { Swift.min(Swift.max($0, 0) / maxV, 1) }
    }

    /// A polyline across the full width, values clamped to 0…1, y inverted (1 = top).
    static func linePath(_ values: [Double], in size: CGSize) -> Path {
        var path = Path()
        guard values.count > 1, size.width > 0, size.height > 0 else { return path }
        let stepX = size.width / CGFloat(values.count - 1)
        for (i, value) in values.enumerated() {
            let x = CGFloat(i) * stepX
            let y = size.height * (1 - CGFloat(Swift.min(Swift.max(value, 0), 1)))
            if i == 0 { path.move(to: CGPoint(x: x, y: y)) } else { path.addLine(to: CGPoint(x: x, y: y)) }
        }
        return path
    }

    /// The line path closed down to the baseline, for a filled area.
    static func areaPath(_ values: [Double], in size: CGSize) -> Path {
        var path = linePath(values, in: size)
        guard values.count > 1, size.width > 0, size.height > 0 else { return path }
        let stepX = size.width / CGFloat(values.count - 1)
        path.addLine(to: CGPoint(x: CGFloat(values.count - 1) * stepX, y: size.height))
        path.addLine(to: CGPoint(x: 0, y: size.height))
        path.closeSubpath()
        return path
    }

    /// The blend fraction toward white a series color needs to read on the
    /// graph's dark plate, given its perceived luminance (0…1): bright colors
    /// need none; dark ones get a fixed lift that preserves their hue. Pure.
    static func whiteLift(forLuminance luminance: Double) -> Double {
        luminance >= 0.35 ? 0 : 0.55
    }

    // MARK: LED-meter + gauge math (pure)

    /// A hi-fi meter's color zones, bottom to top: green, amber, red.
    enum LEDZone: Equatable { case green, amber, red }

    /// How many of an `count`-segment LED column light for `value` (0…1).
    /// Any nonzero value lights at least the bottom segment — plain rounding
    /// left an idle machine (< 6.25% on 8 segments) showing dead columns,
    /// which on a hi-fi meter reads as "broken" (FAB-V7).
    static func litSegments(value: Double, count: Int) -> Int {
        guard count > 0 else { return 0 }
        let clamped = Swift.min(Swift.max(value, 0), 1)
        let rounded = Int((clamped * Double(count)).rounded())
        return Swift.max(clamped > 0 ? 1 : 0, rounded)
    }

    /// The zone of segment `index` (0 = bottom) in an `count`-segment column:
    /// green below 60% of the scale, amber to 85%, red above — matching the
    /// bars style's thresholds.
    static func ledZone(index: Int, count: Int) -> LEDZone {
        guard count > 0 else { return .green }
        let fraction = (Double(index) + 0.5) / Double(count)
        if fraction >= 0.85 { return .red }
        if fraction >= 0.6 { return .amber }
        return .green
    }

    /// The gauge needle's angle for `value` (0…1), in radians clockwise from
    /// 12 o'clock (`ClockGeometry.point` convention): a ±60° sweep centered up.
    static func gaugeAngle(_ value: Double) -> Double {
        (Swift.min(Swift.max(value, 0), 1) - 0.5) * (2 * .pi / 3)
    }

    /// A compact throughput label: `0`, `<1K`, `64K`, `1.2M` (1024-based,
    /// bytes/s). A trickle below 1 KiB/s reads as `<1K` rather than a hard `0`,
    /// so live-but-quiet traffic is distinguishable from silence (FAB-V7).
    static func formatRate(_ bytesPerSecond: Double) -> String {
        let v = Swift.max(bytesPerSecond, 0)
        if v >= 1024 * 1024 { return String(format: "%.1fM", v / (1024 * 1024)) }
        if v >= 1024 { return String(format: "%.0fK", v / 1024) }
        if v > 0 { return "<1K" }
        return "0"
    }
}
