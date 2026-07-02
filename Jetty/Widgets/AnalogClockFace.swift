import SwiftUI

/// An analog clock dial drawn with `Canvas`, themed by `ClockFaceStyle`: the
/// original minimal glass face plus dials *inspired by* iconic watches — a
/// clean station-style dial ("Clock Face 2000"), the mid-90s rainbow-era Mac
/// wristwatch, an 80s Memphis-style Swatch, and an early-90s translucent
/// "jelly" watch — each tweaked enough to be its own design. Pure drawing from
/// the given `date`; angle math lives in `ClockGeometry`.
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
            case .face2000: drawFace2000(context, center: center, radius: radius, rim: rim, angles: angles)
            case .retroMac: drawRetroMac(context, center: center, radius: radius, rim: rim, angles: angles)
            case .memphis: drawMemphis(context, center: center, radius: radius, rim: rim, angles: angles)
            case .jelly: drawJelly(context, center: center, radius: radius, rim: rim, angles: angles)
            case .colorTime: drawColorTime(context, center: center, radius: radius, rim: rim, angles: angles)
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

    /// "Clock Face 2000": a station-style dial of our own — silvery gradient
    /// face, rounded slate batons, and an orange second hand with an open ring
    /// near the tip (pointedly *not* a red lollipop).
    private func drawFace2000(_ ctx: GraphicsContext, center: CGPoint, radius: CGFloat,
                              rim: CGFloat, angles: ClockGeometry.HandAngles) {
        let slate = Color(red: 0.16, green: 0.18, blue: 0.22)
        let orange = Color(red: 0.95, green: 0.45, blue: 0.10)
        let face = Path(ellipseIn: dialRect(center: center, radius: radius))
        ctx.fill(face, with: .radialGradient(
            Gradient(colors: [.white, Color(white: 0.84)]),
            center: center, startRadius: 0, endRadius: radius))
        ctx.stroke(face, with: .color(Color(white: 0.62)), lineWidth: rim)
        // Minute ticks smear into noise below ~16pt of radius, so skip them there.
        if radius >= 16 {
            tickRing(ctx, center: center, radius: radius, count: 60, from: 0.88, to: 0.94,
                     width: max(0.4, radius * 0.018), color: slate.opacity(0.55))
        }
        tickRing(ctx, center: center, radius: radius, count: 12, from: 0.72, to: 0.94,
                 width: max(1, radius * 0.06), color: slate.opacity(0.9), cap: .round)
        hand(ctx, center: center, angle: angles.hour, length: radius * 0.52, tail: radius * 0.14,
             width: max(1.5, radius * 0.10), color: slate)
        hand(ctx, center: center, angle: angles.minute, length: radius * 0.80, tail: radius * 0.14,
             width: max(1, radius * 0.075), color: slate)
        if showSeconds {
            let ringWidth = max(0.8, radius * 0.035)
            hand(ctx, center: center, angle: angles.second, length: radius * 0.61, tail: radius * 0.18,
                 width: ringWidth, color: orange)
            // The open ring near the tip, then a short pointer past it.
            let ringCenter = ClockGeometry.point(center: center, angle: angles.second, distance: radius * 0.70)
            ctx.stroke(Path(ellipseIn: dialRect(center: ringCenter, radius: radius * 0.09)),
                       with: .color(orange), lineWidth: ringWidth)
            var pointer = Path()
            pointer.move(to: ClockGeometry.point(center: center, angle: angles.second, distance: radius * 0.79))
            pointer.addLine(to: ClockGeometry.point(center: center, angle: angles.second, distance: radius * 0.88))
            ctx.stroke(pointer, with: .color(orange),
                       style: StrokeStyle(lineWidth: ringWidth, lineCap: .round))
        }
        hub(ctx, center: center, radius: radius * 0.055, color: slate)
        hub(ctx, center: center, radius: radius * 0.028, color: orange)
    }

    /// The mid-90s Mac wristwatch: a metallic blue studded bezel, white dial,
    /// fat green triangle hour hand, red baton minute hand, yellow squiggle
    /// second hand, and a little rainbow chip below 12 (sans fruit).
    private func drawRetroMac(_ ctx: GraphicsContext, center: CGPoint, radius: CGFloat,
                              rim: CGFloat, angles: ClockGeometry.HandAngles) {
        let green = Color(red: 0.13, green: 0.62, blue: 0.25)
        let red = Color(red: 0.90, green: 0.12, blue: 0.10)
        let yellow = Color(red: 0.99, green: 0.78, blue: 0.05)

        // Anodized-blue bezel: a filled disc with a diagonal sheen; the white
        // dial covers its middle, leaving a ring.
        let outer = Path(ellipseIn: dialRect(center: center, radius: radius))
        ctx.fill(outer, with: .linearGradient(
            Gradient(colors: [Color(red: 0.55, green: 0.75, blue: 0.98),
                              Color(red: 0.10, green: 0.32, blue: 0.72)]),
            startPoint: CGPoint(x: center.x - radius, y: center.y - radius),
            endPoint: CGPoint(x: center.x + radius, y: center.y + radius)))
        ctx.stroke(outer, with: .color(.black.opacity(0.35)), lineWidth: max(0.5, radius * 0.03))

        let dialR = radius * 0.78
        let dial = Path(ellipseIn: dialRect(center: center, radius: dialR))
        ctx.fill(dial, with: .color(.white))
        ctx.stroke(dial, with: .color(.black.opacity(0.2)), lineWidth: max(0.5, radius * 0.02))

        // Silver studs around the bezel…
        for stud in 0..<8 {
            let p = ClockGeometry.point(center: center, angle: Double(stud) / 8 * 2 * .pi,
                                        distance: radius * 0.89)
            let r = radius * 0.045
            ctx.fill(Path(ellipseIn: dialRect(center: p, radius: r)), with: .color(Color(white: 0.88)))
            ctx.stroke(Path(ellipseIn: dialRect(center: p, radius: r)),
                       with: .color(.black.opacity(0.3)), lineWidth: max(0.3, r * 0.3))
        }
        // …and four on the dial at the quarters.
        for quarter in 0..<4 {
            let p = ClockGeometry.point(center: center, angle: Double(quarter) / 4 * 2 * .pi,
                                        distance: dialR * 0.72)
            let r = dialR * 0.055
            ctx.fill(Path(ellipseIn: dialRect(center: p, radius: r)), with: .color(Color(white: 0.80)))
            ctx.stroke(Path(ellipseIn: dialRect(center: p, radius: r)),
                       with: .color(.black.opacity(0.25)), lineWidth: max(0.3, r * 0.3))
        }

        // A six-stripe rainbow chip below 12 — the era's colors, no logo.
        let stripes = [red, Color.orange, yellow, green,
                       Color(red: 0.20, green: 0.45, blue: 0.95),
                       Color(red: 0.50, green: 0.25, blue: 0.75)]
        let chipW = dialR * 0.34
        let stripeH = dialR * 0.045
        let chipTop = center.y - dialR * 0.60
        for (i, color) in stripes.enumerated() {
            let rect = CGRect(x: center.x - chipW / 2, y: chipTop + stripeH * CGFloat(i),
                              width: chipW, height: stripeH)
            ctx.fill(Path(roundedRect: rect, cornerRadius: stripeH * 0.3), with: .color(color))
        }

        triangleHand(ctx, center: center, angle: angles.hour, length: dialR * 0.58,
                     halfBase: dialR * 0.17, color: green)
        hand(ctx, center: center, angle: angles.minute, length: dialR * 0.88,
             width: max(1.5, dialR * 0.14), color: red, cap: .butt)
        if showSeconds {
            squiggleHand(ctx, center: center, angle: angles.second, length: dialR * 0.82,
                         amplitude: dialR * 0.085, width: max(1, dialR * 0.06), color: yellow)
        }
        hub(ctx, center: center, radius: dialR * 0.14, color: yellow)
        ctx.stroke(Path(ellipseIn: dialRect(center: center, radius: dialR * 0.14)),
                   with: .color(.black.opacity(0.15)), lineWidth: max(0.3, dialR * 0.02))
    }

    /// An 80s Memphis-style Swatch: cream dial with pastel shapes (a pink
    /// sector, a mint chunk, lavender dots), confetti quarter markers, and
    /// black-outlined primary-colored hands.
    private func drawMemphis(_ ctx: GraphicsContext, center: CGPoint, radius: CGFloat,
                             rim: CGFloat, angles: ClockGeometry.HandAngles) {
        let cream = Color(red: 0.97, green: 0.94, blue: 0.86)
        let red = Color(red: 0.90, green: 0.20, blue: 0.16)
        let teal = Color(red: 0.0, green: 0.62, blue: 0.58)
        let yellow = Color(red: 0.99, green: 0.75, blue: 0.10)
        let violet = Color(red: 0.45, green: 0.25, blue: 0.75)
        let pink = Color(red: 0.98, green: 0.68, blue: 0.78)
        let mint = Color(red: 0.55, green: 0.85, blue: 0.72)
        let lavender = Color(red: 0.72, green: 0.60, blue: 0.92)
        let face = Path(ellipseIn: dialRect(center: center, radius: radius))
        ctx.fill(face, with: .color(cream))

        // Pastel furniture under the markers: a pink sector from 0:30 to 2:30…
        var wedge = Path()
        wedge.move(to: center)
        for step in 0...12 {
            let clockAngle = (0.5 + 2.0 * Double(step) / 12.0) / 12.0 * 2 * .pi
            wedge.addLine(to: ClockGeometry.point(center: center, angle: clockAngle,
                                                  distance: radius * 0.94))
        }
        wedge.closeSubpath()
        ctx.fill(wedge, with: .color(pink.opacity(0.55)))
        // …a mint chunk around 7 o'clock…
        var chunk = Path()
        chunk.move(to: ClockGeometry.point(center: center, angle: 7.0 / 12 * 2 * .pi, distance: radius * 0.80))
        chunk.addLine(to: ClockGeometry.point(center: center, angle: 8.2 / 12 * 2 * .pi, distance: radius * 0.52))
        chunk.addLine(to: ClockGeometry.point(center: center, angle: 6.3 / 12 * 2 * .pi, distance: radius * 0.42))
        chunk.closeSubpath()
        ctx.fill(chunk, with: .color(mint.opacity(0.7)))
        // …and a sprinkle of lavender dots.
        for (h, d) in [(10.4, 0.55), (4.7, 0.60), (9.2, 0.30)] {
            let p = ClockGeometry.point(center: center, angle: h / 12 * 2 * .pi,
                                        distance: radius * CGFloat(d))
            ctx.fill(Path(ellipseIn: dialRect(center: p, radius: radius * 0.045)),
                     with: .color(lavender.opacity(0.8)))
        }

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

        outlinedHand(ctx, center: center, angle: angles.hour, length: radius * 0.50,
                     width: max(1.5, radius * 0.10), color: yellow)
        outlinedHand(ctx, center: center, angle: angles.minute, length: radius * 0.78,
                     width: max(1, radius * 0.08), color: red)
        if showSeconds {
            hand(ctx, center: center, angle: angles.second, length: radius * 0.80, tail: radius * 0.15,
                 width: max(0.6, radius * 0.025), color: .black.opacity(0.9))
            let counterweight = ClockGeometry.point(center: center, angle: angles.second + .pi,
                                                    distance: radius * 0.15)
            ctx.fill(Path(ellipseIn: dialRect(center: counterweight, radius: radius * 0.045)),
                     with: .color(teal))
        }
        hub(ctx, center: center, radius: radius * 0.07, color: .white)
        ctx.stroke(Path(ellipseIn: dialRect(center: center, radius: radius * 0.07)),
                   with: .color(.black.opacity(0.9)), lineWidth: max(0.8, radius * 0.025))
    }

    /// An early-90s translucent "jelly" watch: a see-through dial and chunky
    /// double rim tinted with the accent color, a glossy shine arc, and twelve
    /// rainbow dot markers.
    private func drawJelly(_ ctx: GraphicsContext, center: CGPoint, radius: CGFloat,
                           rim: CGFloat, angles: ClockGeometry.HandAngles) {
        let magenta = Color(red: 1.0, green: 0.25, blue: 0.55)
        let face = Path(ellipseIn: dialRect(center: center, radius: radius))
        ctx.fill(face, with: .color(tint.opacity(0.30)))
        ctx.fill(face, with: .radialGradient(
            Gradient(colors: [.white.opacity(0.22), .white.opacity(0.0)]),
            center: CGPoint(x: center.x, y: center.y - radius * 0.35),
            startRadius: 0, endRadius: radius * 1.15))
        // The molded-plastic shine: a fat soft arc across the upper dial.
        var shine = Path()
        for step in 0...10 {
            let hours = -2.0 + 3.0 * Double(step) / 10.0   // 10 o'clock → 1 o'clock
            let p = ClockGeometry.point(center: center, angle: hours / 12 * 2 * .pi,
                                        distance: radius * 0.58)
            if step == 0 { shine.move(to: p) } else { shine.addLine(to: p) }
        }
        ctx.stroke(shine, with: .color(.white.opacity(0.28)),
                   style: StrokeStyle(lineWidth: max(1.5, radius * 0.10), lineCap: .round,
                                      lineJoin: .round))
        // Chunky tinted rim with a thin white inner ring — layered jelly plastic.
        ctx.stroke(face, with: .color(tint.opacity(0.9)), lineWidth: rim)
        ctx.stroke(Path(ellipseIn: dialRect(center: center, radius: radius - rim * 0.9)),
                   with: .color(.white.opacity(0.35)), lineWidth: max(0.5, rim * 0.35))
        // Rainbow dot markers.
        for tick in 0..<12 {
            let p = ClockGeometry.point(center: center, angle: Double(tick) / 12 * 2 * .pi,
                                        distance: radius * 0.80)
            ctx.fill(Path(ellipseIn: dialRect(center: p, radius: max(0.8, radius * 0.05))),
                     with: .color(Color(hue: Double(tick) / 12, saturation: 0.75,
                                        brightness: 0.95).opacity(0.9)))
        }
        hand(ctx, center: center, angle: angles.hour, length: radius * 0.5,
             width: max(1.5, radius * 0.09), color: .white.opacity(0.95))
        hand(ctx, center: center, angle: angles.minute, length: radius * 0.74,
             width: max(1, radius * 0.06), color: .white.opacity(0.9))
        if showSeconds {
            hand(ctx, center: center, angle: angles.second, length: radius * 0.78,
                 width: max(0.5, radius * 0.03), color: magenta)
        }
        hub(ctx, center: center, radius: radius * 0.07, color: .white)
        hub(ctx, center: center, radius: radius * 0.035, color: tint)
    }

    /// "Color Time", after Tian Harlan's 70s Chromachron: a black dial with a
    /// 12-color hour ring, and a 30° wedge that sweeps like an hour hand,
    /// revealing the color wheel hidden under the dial. No hands — the color
    /// *is* the time (deliberately approximate).
    private func drawColorTime(_ ctx: GraphicsContext, center: CGPoint, radius: CGFloat,
                               rim: CGFloat, angles: ClockGeometry.HandAngles) {
        // The 12 hour colors, red-orange at the top and running clockwise.
        func hourColor(_ i: Int) -> Color {
            Color(hue: (Double(i) / 12 + 0.02).truncatingRemainder(dividingBy: 1),
                  saturation: 0.80, brightness: 0.95)
        }
        let face = Path(ellipseIn: dialRect(center: center, radius: radius))
        ctx.fill(face, with: .color(.black.opacity(0.92)))
        ctx.stroke(face, with: .color(Color(white: 0.35)), lineWidth: rim)

        // The hour ring: one colored arc per hour, with small gaps between.
        for i in 0..<12 {
            let mid = Double(i) / 12 * 2 * .pi
            ctx.stroke(arc(center: center, radius: radius * 0.92,
                           from: mid - .pi / 14, to: mid + .pi / 14),
                       with: .color(hourColor(i)),
                       style: StrokeStyle(lineWidth: max(1, radius * 0.075), lineCap: .butt))
        }

        // The sweeping wedge: clip to it and paint the full color wheel, so as
        // the wedge crosses an hour boundary it reveals both colors at once.
        let wedge = sector(center: center, radius: radius * 0.86,
                           mid: angles.hour, halfWidth: .pi / 12)
        var reveal = ctx
        reveal.clip(to: wedge)
        for i in 0..<12 {
            let mid = Double(i) / 12 * 2 * .pi
            reveal.fill(sector(center: center, radius: radius * 0.86, mid: mid, halfWidth: .pi / 12),
                        with: .color(hourColor(i)))
        }

        // Hub: a black disc ringed by the whole color wheel in miniature.
        hub(ctx, center: center, radius: radius * 0.10, color: .black)
        ctx.stroke(Path(ellipseIn: dialRect(center: center, radius: radius * 0.10)),
                   with: .conicGradient(Gradient(colors: (0...12).map { hourColor($0 % 12) }),
                                        center: center),
                   lineWidth: max(0.8, radius * 0.035))
    }

    // MARK: Drawing helpers

    /// A polyline arc between two clock angles (0 = up, clockwise) at `radius`.
    private func arc(center: CGPoint, radius: CGFloat, from: Double, to: Double) -> Path {
        var path = Path()
        let steps = 8
        for i in 0...steps {
            let angle = from + (to - from) * Double(i) / Double(steps)
            let p = ClockGeometry.point(center: center, angle: angle, distance: radius)
            if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
        }
        return path
    }

    /// A pie sector spanning `mid ± halfWidth` (clock angles) out to `radius`.
    private func sector(center: CGPoint, radius: CGFloat, mid: Double, halfWidth: Double) -> Path {
        var path = Path()
        path.move(to: center)
        let steps = 8
        for i in 0...steps {
            let angle = mid - halfWidth + 2 * halfWidth * Double(i) / Double(steps)
            path.addLine(to: ClockGeometry.point(center: center, angle: angle, distance: radius))
        }
        path.closeSubpath()
        return path
    }

    /// The square bounding `radius` around `center` (for circles/dials).
    private func dialRect(center: CGPoint, radius: CGFloat) -> CGRect {
        CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
    }

    /// A ring of `count` radial ticks between `from`·radius and `to`·radius.
    private func tickRing(_ ctx: GraphicsContext, center: CGPoint, radius: CGFloat, count: Int,
                          from inner: CGFloat, to outer: CGFloat, width: CGFloat, color: Color,
                          cap: CGLineCap = .butt) {
        for tick in 0..<count {
            let angle = Double(tick) / Double(count) * 2 * .pi
            var path = Path()
            path.move(to: ClockGeometry.point(center: center, angle: angle, distance: radius * inner))
            path.addLine(to: ClockGeometry.point(center: center, angle: angle, distance: radius * outer))
            ctx.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: width, lineCap: cap))
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

    /// A hand with a black outline (Memphis loved outlines): the black pass is
    /// slightly wider, the colored pass sits on top.
    private func outlinedHand(_ ctx: GraphicsContext, center: CGPoint, angle: Double,
                              length: CGFloat, width: CGFloat, color: Color) {
        hand(ctx, center: center, angle: angle, length: length,
             width: width + max(1, width * 0.45), color: .black.opacity(0.9))
        hand(ctx, center: center, angle: angle, length: length, width: width, color: color)
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
