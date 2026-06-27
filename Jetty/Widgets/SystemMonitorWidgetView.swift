import SwiftUI

/// A CPU + memory meter tile (ND-3): two slim bars (load and memory pressure) with
/// labels, sampled every 2s via `TimelineView`. The bar fill shifts from the tint to
/// orange to red as it fills, so a glance reads pressure.
struct SystemMonitorWidgetView: View {
    var height: CGFloat
    var tint: Color

    var body: some View {
        TimelineView(.periodic(from: .now, by: 2)) { _ in
            let load = SystemStats.normalizedLoad()
            let mem = SystemStats.memoryUsedFraction()
            HStack(spacing: 6) {
                meter(label: "CPU", value: load)
                meter(label: "RAM", value: mem)
            }
            .padding(.horizontal, 6)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .contentShape(Rectangle())
        .help("CPU load and memory usage")
    }

    private func meter(label: String, value: Double) -> some View {
        let clamped = min(max(value, 0), 1)
        return VStack(spacing: 2) {
            Text(label)
                .font(.system(size: max(7, height * 0.16), weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
            GeometryReader { geo in
                ZStack(alignment: .bottom) {
                    Capsule().fill(Color.primary.opacity(0.15))
                    Capsule().fill(barColor(clamped))
                        .frame(height: max(2, geo.size.height * clamped))
                }
            }
            .frame(width: max(5, height * 0.14))
            Text("\(Int((clamped * 100).rounded()))")
                .font(.system(size: max(7, height * 0.16), weight: .medium, design: .rounded))
                .monospacedDigit()
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
