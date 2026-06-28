import SwiftUI

/// A CPU + memory meter tile (ND-3): two slim bars (load and memory pressure) with
/// labels, fed by the shared `LiveSystemStats` sampler (one read per tick across all
/// displays — ISSUE-5). The bar fill shifts from the tint to orange to red as it
/// fills, so a glance reads pressure.
struct SystemMonitorWidgetView: View {
    var height: CGFloat
    var tint: Color
    @ObservedObject private var stats = LiveSystemStats.shared

    var body: some View {
        HStack(spacing: 6) {
            meter(label: "CPU", value: stats.load)
            meter(label: "RAM", value: stats.memory)
        }
        .padding(.horizontal, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .help("CPU load and memory usage")
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
}
