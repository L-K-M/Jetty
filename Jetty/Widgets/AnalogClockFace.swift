import SwiftUI

/// An analog clock dial drawn with `Canvas`, themed by `ClockFaceStyle`: the
/// original minimal glass face plus dials modeled on iconic watches — the Swiss
/// railway station clock, the mid-90s rainbow-era Mac wristwatch, an 80s
/// Memphis-style Swatch, and an early-90s translucent "jelly" watch. Pure
/// drawing from the given `date`; angle math lives in `ClockGeometry`.
///
/// The dial is **inset by half the rim's stroke width** (the overhanging half):
/// `Canvas` clips to its own bounds, and a dial drawn out to the bounds circle
/// loses the outer half of its centered rim stroke exactly at 12/3/6/9 — the
/// visible "cut off" flat spots.
struct AnalogClockFace: View {
    let date: Date
    var style: ClockFaceStyle
    var showSeconds: Bool
    var tint: Color

    var body: some View {
        Canvas { context, size in
            let side = min(size.width, size.height)
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let rim = rimWidth(forSide: side)
            // Half the rim overhangs the dial circle on each side; pull the dial in
            // by that much (plus a hair for antialiasing) so nothing gets clipped.
            let radius = (side - rim) / 2 - 0.5
            guard radius > 2 else { return }

            let comps = Calendar.current.dateComponents([.hour, .minute, .second], from: date)
            let angles = ClockGeometry.handAngles(hour: comps.hour ?? 0,
                                                  minute: comps.minute ?? 0,
                                                  second: comps.second ?? 0)
            switch style {
            case .swiss: drawSwiss(context, center: center, radius: radius, rim: rim, angles: angles)
            case .retroMac: drawRetroMac(context, center: center, radius: radius, rim: rim, angles: angles)
            case .memphis: drawMemphis(context, center: center, radius: radius, rim: rim, angles: angles)
            case .jelly: drawJelly(context, center: center, radius: radius, rim: rim, angles: angles)
            default: drawClassic(context, center: center, radius: radius, rim: rim, angles: angles)
            }
        }
        .contentShape(Rectangle())
    }

    /// The rim stroke width per style — chunky translucent plastic for jelly,
    /// hairline bezels elsewhere. Sized from the canvas side (not the radius,
    /// which itself depends on this).
    private func rimWidth(forSide side: CGFloat) -> CGFloat {
        switch style {
        case .jelly: return max(1.5, side * 0.05)
        case .classic: return max(1, side * 0.03)
        default: return max(1, side * 0.02)
        }
    }

    // MARK: Faces

    /// The original Jetty face: a dark glassy disc with a soft top highlight so
    /// the hands read clearly against the dock glass.
    private func drawClassic(_ ctx: GraphicsContext, center: CGPoint, radius: CGFloat,
                             rim: CGFloat, angles: ClockGeometry.HandAngles) {
        let face = Path(ellipseIn: dialRect(center: center, radius: radius))
        ctx.fill(face, with: .color(.black.opacity(0.28)))
        ctx.fill(face, with: .radialGradient(
            Gradient(colors: [.white.opacity(0.16), .white.opacity(0.0)]),
            center: CGPoint(x: center.x, y: center.y - radius * 0.35),
            startRadius: 0, endRadius: radius * 1.15))
        ctx.stroke(face, with: .color(.white.opacity(0.55)), lineWidth: rim)
        tickRing(ctx, center: center, radius: radius, count: 12, from: 0.78, to: 0.9,
                 width: max(0.5, radius * 0.04), color: .white.opacity(0.5))
        hand(ctx, center: center, angle: angles.hour, length: radius * 0.5,
             width: max(1.5, radius * 0.09), color: .white)
        hand(ctx, center: center, angle: angles.minute, length: radius * 0.78,
             width: max(1, radius * 0.06), color: .white)
        if showSeconds {
            hand(ctx, center: center, angle: angles.second, length: radius * 0.82,
                 width: max(0.5, radius * 0.03), color: tint)
        }
        hub(ctx, center: center, radius: radius * 0.08, color: tint)
    }

    /// The Swiss railway station clock: white dial, bold black batons, and the
    /// red lollipop second hand.
    private func drawSwiss(_ ctx: GraphicsContext, center: CGPoint, radius: CGFloat,
                           rim: CGFloat, angles: ClockGeometry.HandAngles) {
        let red = Color(red: 0.86, green: 0.12, blue: 0.13)
        let face = Path(ellipseIn: dialRect(center: center, radius: radius))
        ctx.fill(face, with: .color(.white))
        ctx.stroke(face, with: .color(.black.opacity(0.25)), lineWidth: rim)
        // Minute ticks smear into noise below ~16pt of radius, so skip them there.
        if radius >= 16 {
            tickRing(ctx, center: center, radius: radius, count: 60, from: 0.86, to: 0.94,
                     width: max(0.4, radius * 0.02), color: .black.opacity(0.8))
        }
        tickRing(ctx, center: center, radius: radius, count: 12, from: 0.70, to: 0.94,
                 width: max(1, radius * 0.075), color: .black.opacity(0.9))
        hand(ctx, center: center, angle: angles.hour, length: radius * 0.55, tail: radius * 0.16,
             width: max(1.5, radius * 0.105), color: .black.opacity(0.95), cap: .butt)
        hand(ctx, center: center, angle: angles.minute, length: radius * 0.84, tail: radius * 0.16,
             width: max(1, radius * 0.08), color: .black.opacity(0.95), cap: .butt)
        if showSeconds {
            hand(ctx, center: center, angle: angles.second, length: radius * 0.60, tail: radius * 0.20,
                 width: max(0.8, radius * 0.035), color: red)
            let disc = ClockGeometry.point(center: center, angle: angles.second, distance: radius * 0.60)
            ctx.fill(Path(ellipseIn: dialRect(center: disc, radius: radius * 0.10)), with: .color(red))
        }
        hub(ctx, center: center, radius: radius * 0.05, color: .black.opacity(0.95))
    }

    /// The mid-90s Mac wristwatch: white dial, green triangle hour hand, red
    /// baton minute hand, and the yellow squiggle second hand.
    private func drawRetroMac(_ ctx: GraphicsContext, center: CGPoint, radius: CGFloat,
                              rim: CGFloat, angles: ClockGeometry.HandAngles) {
        let green = Color(red: 0.15, green: 0.61, blue: 0.28)
        let red = Color(red: 0.88, green: 0.15, blue: 0.13)
        let yellow = Color(red: 0.98, green: 0.75, blue: 0.05)
        let face = Path(ellipseIn: dialRect(center: center, radius: radius))
        ctx.fill(face, with: .color(.white))
        ctx.stroke(face, with: .color(.black.opacity(0.2)), lineWidth: rim)
        // Four polished dots at the quarters, standing in for the original's studs.
        for quarter in 0..<4 {
            let p = ClockGeometry.point(center: center, angle: Double(quarter) / 4 * 2 * .pi,
                                        distance: radius * 0.84)
            ctx.fill(Path(ellipseIn: dialRect(center: p, radius: radius * 0.045)),
                     with: .color(.black.opacity(0.25)))
        }
        triangleHand(ctx, center: center, angle: angles.hour, length: radius * 0.52,
                     halfBase: radius * 0.11, color: green)
        hand(ctx, center: center, angle: angles.minute, length: radius * 0.80,
             width: max(1, radius * 0.09), color: red)
        if showSeconds {
            squiggleHand(ctx, center: center, angle: angles.second, length: radius * 0.76,
                         amplitude: radius * 0.055, width: max(0.8, radius * 0.05), color: yellow)
        }
        hub(ctx, center: center, radius: radius * 0.085, color: yellow)
    }

    /// An 80s Memphis-style Swatch: cream dial with confetti-shape markers at the
    /// quarters and primary-colored hands.
    private func drawMemphis(_ ctx: GraphicsContext, center: CGPoint, radius: CGFloat,
                             rim: CGFloat, angles: ClockGeometry.HandAngles) {
        let cream = Color(red: 0.97, green: 0.94, blue: 0.86)
        let red = Color(red: 0.90, green: 0.20, blue: 0.16)
        let teal = Color(red: 0.0, green: 0.62, blue: 0.58)
        let yellow = Color(red: 0.99, green: 0.75, blue: 0.10)
        let violet = Color(red: 0.45, green: 0.25, blue: 0.75)
        let blue = Color(red: 0.13, green: 0.31, blue: 0.78)
        let face = Path(ellipseIn: dialRect(center: center, radius: radius))
        ctx.fill(face, with: .color(cream))
        ctx.stroke(face, with: .color(.black.opacity(0.85)), lineWidth: rim)

        // Quarter markers: dot, square, triangle, dot — Memphis confetti.
        let quarterDist = radius * 0.80
        let top = ClockGeometry.point(center: center, angle: 0, distance: quarterDist)
        ctx.fill(Path(ellipseIn: dialRect(center: top, radius: radius * 0.075)), with: .color(red))
        let right = ClockGeometry.point(center: center, angle: .pi / 2, distance: quarterDist)
        let squareHalf = radius * 0.07
        ctx.fill(Path(CGRect(x: right.x - squareHalf, y: right.y - squareHalf,
                             width: squareHalf * 2, height: squareHalf * 2)), with: .color(teal))
        let bottom = ClockGeometry.point(center: center, angle: .pi, distance: quarterDist)
        let s = radius * 0.09
        var tri = Path()
        tri.move(to: CGPoint(x: bottom.x, y: bottom.y - s))
        tri.addLine(to: CGPoint(x: bottom.x - s * 0.87, y: bottom.y + s * 0.5))
        tri.addLine(to: CGPoint(x: bottom.x + s * 0.87, y: bottom.y + s * 0.5))
        tri.closeSubpath()
        ctx.fill(tri, with: .color(yellow))
        let left = ClockGeometry.point(center: center, angle: 3 * .pi / 2, distance: quarterDist)
        ctx.fill(Path(ellipseIn: dialRect(center: left, radius: radius * 0.06)), with: .color(violet))
        // Small black dots for the remaining hours.
        for tick in 0..<12 where tick % 3 != 0 {
            let p = ClockGeometry.point(center: center, angle: Double(tick) / 12 * 2 * .pi,
                                        distance: radius * 0.82)
            ctx.fill(Path(ellipseIn: dialRect(center: p, radius: max(0.5, radius * 0.025))),
                     with: .color(.black.opacity(0.8)))
        }

        hand(ctx, center: center, angle: angles.hour, length: radius * 0.5,
             width: max(1.5, radius * 0.095), color: blue)
        hand(ctx, center: center, angle: angles.minute, length: radius * 0.78,
             width: max(1, radius * 0.07), color: red)
        if showSeconds {
            hand(ctx, center: center, angle: angles.second, length: radius * 0.80,
                 width: max(0.6, radius * 0.03), color: teal)
        }
        hub(ctx, center: center, radius: radius * 0.06, color: .black.opacity(0.9))
    }

    /// An early-90s translucent "jelly" watch: a see-through dial and chunky rim
    /// tinted with the user's accent color.
    private func drawJelly(_ ctx: GraphicsContext, center: CGPoint, radius: CGFloat,
                           rim: CGFloat, angles: ClockGeometry.HandAngles) {
        let magenta = Color(red: 1.0, green: 0.25, blue: 0.55)
        let face = Path(ellipseIn: dialRect(center: center, radius: radius))
        ctx.fill(face, with: .color(tint.opacity(0.30)))
        ctx.fill(face, with: .radialGradient(
            Gradient(colors: [.white.opacity(0.25), .white.opacity(0.0)]),
            center: CGPoint(x: center.x, y: center.y - radius * 0.35),
            startRadius: 0, endRadius: radius * 1.15))
        ctx.stroke(face, with: .color(tint.opacity(0.9)), lineWidth: rim)
        tickRing(ctx, center: center, radius: radius, count: 12, from: 0.72, to: 0.85,
                 width: max(0.5, radius * 0.04), color: .white.opacity(0.75))
        hand(ctx, center: center, angle: angles.hour, length: radius * 0.5,
             width: max(1.5, radius * 0.09), color: .white.opacity(0.95))
        hand(ctx, center: center, angle: angles.minute, length: radius * 0.76,
             width: max(1, radius * 0.06), color: .white.opacity(0.9))
        if showSeconds {
            hand(ctx, center: center, angle: angles.second, length: radius * 0.80,
                 width: max(0.5, radius * 0.03), color: magenta)
        }
        hub(ctx, center: center, radius: radius * 0.07, color: .white)
    }

    // MARK: Drawing helpers

    /// The square bounding `radius` around `center` (for circles/dials).
    private func dialRect(center: CGPoint, radius: CGFloat) -> CGRect {
        CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
    }

    /// A ring of `count` radial ticks between `from`·radius and `to`·radius.
    private func tickRing(_ ctx: GraphicsContext, center: CGPoint, radius: CGFloat, count: Int,
                          from inner: CGFloat, to outer: CGFloat, width: CGFloat, color: Color) {
        for tick in 0..<count {
            let angle = Double(tick) / Double(count) * 2 * .pi
            var path = Path()
            path.move(to: ClockGeometry.point(center: center, angle: angle, distance: radius * inner))
            path.addLine(to: ClockGeometry.point(center: center, angle: angle, distance: radius * outer))
            ctx.stroke(path, with: .color(color), lineWidth: width)
        }
    }

    /// A straight hand from `tail` points behind the center out to `length`.
    private func hand(_ ctx: GraphicsContext, center: CGPoint, angle: Double, length: CGFloat,
                      tail: CGFloat = 0, width: CGFloat, color: Color, cap: CGLineCap = .round) {
        var path = Path()
        path.move(to: ClockGeometry.point(center: center, angle: angle + .pi, distance: tail))
        path.addLine(to: ClockGeometry.point(center: center, angle: angle, distance: length))
        ctx.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: width, lineCap: cap))
    }

    /// A filled isosceles triangle hand: apex at `length`, base straddling the center.
    private func triangleHand(_ ctx: GraphicsContext, center: CGPoint, angle: Double,
                              length: CGFloat, halfBase: CGFloat, color: Color) {
        var path = Path()
        path.move(to: ClockGeometry.point(center: center, angle: angle, distance: length))
        path.addLine(to: ClockGeometry.point(center: center, angle: angle - .pi / 2, distance: halfBase))
        path.addLine(to: ClockGeometry.point(center: center, angle: angle + .pi / 2, distance: halfBase))
        path.closeSubpath()
        ctx.fill(path, with: .color(color))
    }

    /// A wavy second hand: perpendicular sine sway along the hand's direction,
    /// enveloped to zero at both ends so the hub and the tip stay on the true angle.
    private func squiggleHand(_ ctx: GraphicsContext, center: CGPoint, angle: Double,
                              length: CGFloat, amplitude: CGFloat, width: CGFloat, color: Color) {
        var path = Path()
        let steps = 24
        let waves = 2.5
        for i in 0...steps {
            let t = Double(i) / Double(steps)
            let along = ClockGeometry.point(center: center, angle: angle, distance: CGFloat(t) * length)
            let sway = amplitude * CGFloat(sin(.pi * t) * sin(waves * 2 * .pi * t))
            let p = ClockGeometry.point(center: along, angle: angle + .pi / 2, distance: sway)
            if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
        }
        ctx.stroke(path, with: .color(color),
                   style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
    }

    /// The center hub disc.
    private func hub(_ ctx: GraphicsContext, center: CGPoint, radius: CGFloat, color: Color) {
        ctx.fill(Path(ellipseIn: dialRect(center: center, radius: radius)), with: .color(color))
    }
}
