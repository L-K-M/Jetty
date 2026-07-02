import SwiftUI

/// The System Monitor's analog-gauge look: two tiny cream dials with a tick
/// scale, a redline over the last 15%, and a swinging slate needle — little
/// dashboard instruments for CPU and memory. Needle angles are pure
/// (`SystemMonitorGraph.gaugeAngle`); polar math reuses `ClockGeometry`.
struct SystemMonitorGaugeView: View {
    var cpu: Double
    var ram: Double
    var height: CGFloat

    private static let cream = Color(red: 0.96, green: 0.93, blue: 0.85)
    private static let slate = Color(red: 0.16, green: 0.18, blue: 0.22)
    private static let red = Color(red: 0.88, green: 0.18, blue: 0.15)

    var body: some View {
        HStack(spacing: height * 0.14) {
            gauge(label: "CPU", value: cpu)
            gauge(label: "RAM", value: ram)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(plate)
        .padding(2)
    }

    private var plate: some View {
        let shape = RoundedRectangle(cornerRadius: height * 0.16, style: .continuous)
        return shape.fill(Color.black.opacity(0.32))
            .overlay(shape.fill(LinearGradient(colors: [.white.opacity(0.07), .clear],
                                               startPoint: .top, endPoint: .bottom)))
            .overlay(shape.stroke(.white.opacity(0.15), lineWidth: 1))
    }

    private func gauge(label: String, value: Double) -> some View {
        VStack(spacing: 1) {
            Canvas { ctx, size in
                drawDial(ctx, size: size, value: value)
            }
            Text(label)
                .font(.system(size: max(6, height * 0.13), weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.6))
                .tracking(0.5)
        }
    }

    private func drawDial(_ ctx: GraphicsContext, size: CGSize, value: Double) {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let radius = min(size.width, size.height) / 2 - 1
        guard radius > 3 else { return }

        let face = Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius,
                                          width: radius * 2, height: radius * 2))
        ctx.fill(face, with: .color(Self.cream))
        ctx.stroke(face, with: .color(Self.slate.opacity(0.5)), lineWidth: max(0.5, radius * 0.05))

        // The tick scale across the ±60° sweep, and the redline over the last 15%.
        for tick in 0...4 {
            let angle = SystemMonitorGraph.gaugeAngle(Double(tick) / 4)
            var path = Path()
            path.move(to: ClockGeometry.point(center: center, angle: angle, distance: radius * 0.70))
            path.addLine(to: ClockGeometry.point(center: center, angle: angle, distance: radius * 0.86))
            ctx.stroke(path, with: .color(Self.slate.opacity(0.8)), lineWidth: max(0.5, radius * 0.05))
        }
        var redline = Path()
        for step in 0...6 {
            let angle = SystemMonitorGraph.gaugeAngle(0.85 + 0.15 * Double(step) / 6)
            let p = ClockGeometry.point(center: center, angle: angle, distance: radius * 0.78)
            if step == 0 { redline.move(to: p) } else { redline.addLine(to: p) }
        }
        ctx.stroke(redline, with: .color(Self.red.opacity(0.85)),
                   style: StrokeStyle(lineWidth: max(1, radius * 0.12), lineCap: .butt))

        // Needle + hub.
        let needleAngle = SystemMonitorGraph.gaugeAngle(value)
        var needle = Path()
        needle.move(to: ClockGeometry.point(center: center, angle: needleAngle + .pi, distance: radius * 0.20))
        needle.addLine(to: ClockGeometry.point(center: center, angle: needleAngle, distance: radius * 0.80))
        ctx.stroke(needle, with: .color(Self.slate),
                   style: StrokeStyle(lineWidth: max(1, radius * 0.08), lineCap: .round))
        let hub = radius * 0.10
        ctx.fill(Path(ellipseIn: CGRect(x: center.x - hub, y: center.y - hub,
                                        width: hub * 2, height: hub * 2)),
                 with: .color(Self.slate))
    }
}
