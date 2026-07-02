import SwiftUI

/// The System Monitor's oscilloscope look: glowing phosphor traces (CPU green,
/// memory amber, network cyan) over a faint grid on a near-black CRT screen.
/// Pure presentation — the series come in pre-scaled to 0…1; path math lives in
/// `SystemMonitorGraph`.
struct SystemMonitorScopeView: View {
    var cpu: [Double]
    var ram: [Double]
    var net: [Double]
    var cpuValue: Double
    var ramValue: Double
    var netRate: Double
    var showNetwork: Bool
    var height: CGFloat

    private static let phosphor = Color(red: 0.38, green: 1.0, blue: 0.55)
    private static let amber = Color(red: 1.0, green: 0.76, blue: 0.28)
    private static let cyan = Color(red: 0.45, green: 0.92, blue: 1.0)

    var body: some View {
        VStack(spacing: 2) {
            HStack(spacing: 6) {
                readout(percentText(cpuValue), color: Self.phosphor)
                readout(percentText(ramValue), color: Self.amber)
                if showNetwork {
                    readout(SystemMonitorGraph.formatRate(netRate), color: Self.cyan)
                }
                Spacer(minLength: 0)
            }
            .font(.system(size: max(7, height * 0.15), weight: .semibold, design: .monospaced))
            .fixedSize(horizontal: false, vertical: true)

            GeometryReader { geo in
                let size = geo.size
                grid(in: size).stroke(Self.phosphor.opacity(0.13), lineWidth: 0.5)
                trace(cpu, in: size, color: Self.phosphor)
                trace(ram, in: size, color: Self.amber)
                if showNetwork {
                    trace(net, in: size, color: Self.cyan, coreWidth: 1)
                }
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(screen)
        .padding(2)
    }

    /// The CRT: a near-black green-cast screen with a phosphor-tinted bezel line.
    private var screen: some View {
        let shape = RoundedRectangle(cornerRadius: height * 0.16, style: .continuous)
        return shape.fill(Color(red: 0.02, green: 0.06, blue: 0.03).opacity(0.92))
            .overlay(shape.fill(LinearGradient(colors: [.white.opacity(0.05), .clear],
                                               startPoint: .top, endPoint: .bottom)))
            .overlay(shape.stroke(Self.phosphor.opacity(0.35), lineWidth: 1))
    }

    /// A phosphor trace: a wide soft pass for the glow, a thin bright core on top.
    private func trace(_ values: [Double], in size: CGSize, color: Color,
                       coreWidth: CGFloat = 1.3) -> some View {
        ZStack {
            SystemMonitorGraph.linePath(values, in: size)
                .stroke(color.opacity(0.28),
                        style: StrokeStyle(lineWidth: coreWidth + 2.2, lineJoin: .round))
            SystemMonitorGraph.linePath(values, in: size)
                .stroke(color, style: StrokeStyle(lineWidth: coreWidth, lineJoin: .round))
        }
    }

    /// Scope graticule: 6 × 4 divisions.
    private func grid(in size: CGSize) -> Path {
        var path = Path()
        for column in 1..<6 {
            let x = size.width * CGFloat(column) / 6
            path.move(to: CGPoint(x: x, y: 0))
            path.addLine(to: CGPoint(x: x, y: size.height))
        }
        for row in 1..<4 {
            let y = size.height * CGFloat(row) / 4
            path.move(to: CGPoint(x: 0, y: y))
            path.addLine(to: CGPoint(x: size.width, y: y))
        }
        return path
    }

    /// Phosphor-bright readouts are legible on the near-black screen directly.
    private func readout(_ text: String, color: Color) -> some View {
        Text(text)
            .foregroundStyle(color)
            .lineLimit(1)
            .minimumScaleFactor(0.5)
    }

    private func percentText(_ value: Double) -> String {
        "\(Int((min(max(value, 0), 1) * 100).rounded()))"
    }
}
