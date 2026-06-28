import SwiftUI

/// A CPU + memory tile (ND-3), fed by the shared `LiveSystemStats` sampler (one read
/// per tick across all displays — ISSUE-5). Two presentations:
/// - `.bars`: two slim gauges (load + memory pressure), the original compact look.
/// - `.graph`: a time-series sparkline of CPU and memory over the last ~2 minutes,
///   plus an optional network-throughput trace, so the trend reads at a glance.
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
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .help(helpText)
    }

    private var helpText: String {
        style == .graph
            ? "CPU, memory\(showNetwork ? ", and network" : "") over the last couple of minutes"
            : "CPU load and memory usage"
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
                .foregroundStyle(color)
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
        let net = SystemMonitorGraph.autoScaled(samples.map { $0.netDown + $0.netUp },
                                                floor: SystemMonitorGraph.netFloor)
        let labelSize = max(7, height * 0.15)
        // Legend sits in its own row ABOVE the chart so the sparklines never draw over
        // the numbers; the chart fills the space that remains.
        return VStack(spacing: 1) {
            HStack(spacing: 5) {
                legendValue("\(percent(stats.load))", color: tint)
                legendValue("\(percent(stats.memory))", color: ramColor)
                if showNetwork {
                    legendValue(SystemMonitorGraph.formatRate(currentNetRate), color: netColor)
                }
                Spacer(minLength: 0)
            }
            .font(.system(size: labelSize, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .fixedSize(horizontal: false, vertical: true)

            GeometryReader { geo in
                let size = geo.size
                // CPU: filled area + line (the dominant series, in the tint).
                SystemMonitorGraph.areaPath(cpu, in: size)
                    .fill(LinearGradient(colors: [tint.opacity(0.45), tint.opacity(0.04)],
                                         startPoint: .top, endPoint: .bottom))
                SystemMonitorGraph.linePath(cpu, in: size)
                    .stroke(tint, style: StrokeStyle(lineWidth: 1.5, lineJoin: .round))
                // RAM: line only.
                SystemMonitorGraph.linePath(ram, in: size)
                    .stroke(ramColor, style: StrokeStyle(lineWidth: 1.5, lineJoin: .round))
                // Network: thin auto-scaled line.
                if showNetwork {
                    SystemMonitorGraph.linePath(net, in: size)
                        .stroke(netColor.opacity(0.85), style: StrokeStyle(lineWidth: 1, lineJoin: .round))
                }
            }
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 4)
    }

    private func legendValue(_ text: String, color: Color) -> some View {
        Text(text)
            .foregroundStyle(color)
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .shadow(color: .black.opacity(0.5), radius: 1)
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

    /// A compact throughput label: `0`, `64K`, `1.2M` (1024-based, bytes/s).
    static func formatRate(_ bytesPerSecond: Double) -> String {
        let v = Swift.max(bytesPerSecond, 0)
        if v >= 1024 * 1024 { return String(format: "%.1fM", v / (1024 * 1024)) }
        if v >= 1024 { return String(format: "%.0fK", v / 1024) }
        return "0"
    }
}
