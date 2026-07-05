import SwiftUI

/// The System Monitor's hi-fi LED-meter look: one column of stacked segments
/// per metric, lit bottom-up — green through amber into red at the top, unlit
/// segments faintly visible, like an 80s amplifier's level display. The
/// lit-count and zone math is pure (`SystemMonitorGraph`).
struct SystemMonitorLEDView: View {
    var cpu: Double
    var ram: Double
    var height: CGFloat

    private static let segmentCount = 8

    var body: some View {
        HStack(spacing: height * 0.22) {
            column(label: "CPU", value: cpu)
            column(label: "RAM", value: ram)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(plate)
        .padding(2)
    }

    private var plate: some View {
        let shape = RoundedRectangle(cornerRadius: height * 0.16, style: .continuous)
        return shape.fill(Color.black.opacity(0.45))
            .overlay(shape.fill(LinearGradient(colors: [.white.opacity(0.06), .clear],
                                               startPoint: .top, endPoint: .bottom)))
            .overlay(shape.stroke(.white.opacity(0.14), lineWidth: 1))
    }

    private func column(label: String, value: Double) -> some View {
        let lit = SystemMonitorGraph.litSegments(value: value, count: Self.segmentCount)
        return VStack(spacing: 2) {
            VStack(spacing: 1.5) {
                // Top-down rows; row i (from the bottom) lights when i < lit.
                ForEach((0..<Self.segmentCount).reversed(), id: \.self) { index in
                    segment(zone: SystemMonitorGraph.ledZone(index: index, count: Self.segmentCount),
                            isLit: index < lit)
                }
            }
            Text(label)
                .font(.system(size: max(7, height * 0.13), weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.6))
                .tracking(0.5)
        }
    }

    private func segment(zone: SystemMonitorGraph.LEDZone, isLit: Bool) -> some View {
        let color = color(for: zone)
        return RoundedRectangle(cornerRadius: 1, style: .continuous)
            .fill(color.opacity(isLit ? 1.0 : 0.13))
            .frame(width: height * 0.30)
            .frame(maxHeight: .infinity)
            .shadow(color: color.opacity(isLit ? 0.6 : 0), radius: 1.5)
    }

    private func color(for zone: SystemMonitorGraph.LEDZone) -> Color {
        switch zone {
        case .green: return Color(red: 0.30, green: 0.95, blue: 0.40)
        case .amber: return Color(red: 1.0, green: 0.72, blue: 0.20)
        case .red: return Color(red: 1.0, green: 0.28, blue: 0.25)
        }
    }
}
