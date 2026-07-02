import SwiftUI

/// The date/time dock tile (improvement #3). Renders the time and, optionally, the
/// date/weekday — or a tiny **analog face** (ND-4) — ticking via a `TimelineView`
/// so there are no manual timers. String building lives in the pure
/// `ClockFormatter`. See PLAN.md §8.1.
struct ClockWidgetView: View {
    @ObservedObject var preferences: Preferences
    var height: CGFloat

    var body: some View {
        // Seconds/analog tick every second; otherwise tick once a minute, phased to the
        // minute boundary so the shown minute never lags up to ~60 s behind (M29).
        let showsSeconds = preferences.clockShowSeconds || preferences.clockAnalog
        let schedule: PeriodicTimelineSchedule = showsSeconds
            ? .periodic(from: .now, by: 1)
            : .periodic(from: ClockFormatter.minuteStart(), by: 60)
        TimelineView(schedule) { context in
            if preferences.clockAnalog {
                AnalogClockFace(date: context.date,
                                showSeconds: preferences.clockShowSeconds,
                                tint: preferences.tintColor)
                    .frame(width: height * 0.92, height: height * 0.92)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .help("Open Calendar")
            } else {
                digital(date: context.date)
            }
        }
    }

    private func digital(date: Date) -> some View {
        let lines = ClockFormatter.lines(
            for: date,
            use24Hour: preferences.clockUse24Hour,
            showSeconds: preferences.clockShowSeconds,
            showDate: preferences.clockShowDate,
            showWeekday: preferences.clockShowWeekday)

        return VStack(spacing: 1) {
            Text(lines.primary)
                .font(.system(size: max(11, height * 0.32), weight: .semibold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.5)   // "10:00:00 PM" / small tiles must not wrap or clip (F-L7)
            if let secondary = lines.secondary {
                Text(secondary)
                    .font(.system(size: max(8, height * 0.2), weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
            }
        }
        .padding(.horizontal, 8)
        .frame(minWidth: height * 1.4)
        .frame(maxHeight: .infinity)
        .contentShape(Rectangle())
        .help("Open Calendar")
    }
}

/// A minimal analog clock face drawn with `Canvas`: a rim, hour ticks, and
/// hour/minute (and optional second) hands. Pure drawing from the given `date`.
struct AnalogClockFace: View {
    let date: Date
    var showSeconds: Bool
    var tint: Color

    var body: some View {
        Canvas { context, size in
            let radius = min(size.width, size.height) / 2
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let faceRect = CGRect(x: center.x - radius, y: center.y - radius,
                                  width: radius * 2, height: radius * 2)
            let face = Path(ellipseIn: faceRect)

            // Face: a dark glassy disc with a soft top highlight so the hands read
            // clearly against the dock glass (instead of a transparent, low-contrast face).
            context.fill(face, with: .color(.black.opacity(0.28)))
            context.fill(face, with: .radialGradient(
                Gradient(colors: [.white.opacity(0.16), .white.opacity(0.0)]),
                center: CGPoint(x: center.x, y: center.y - radius * 0.35),
                startRadius: 0, endRadius: radius * 1.15))

            // Rim.
            let rim = face
            context.stroke(rim, with: .color(.white.opacity(0.55)), lineWidth: max(1, radius * 0.06))

            // Hour ticks.
            for tick in 0..<12 {
                let angle = Double(tick) / 12 * 2 * .pi
                let outer = point(center: center, angle: angle, distance: radius * 0.9)
                let inner = point(center: center, angle: angle, distance: radius * 0.78)
                var path = Path()
                path.move(to: inner); path.addLine(to: outer)
                context.stroke(path, with: .color(.white.opacity(0.5)), lineWidth: max(0.5, radius * 0.04))
            }

            let comps = Calendar.current.dateComponents([.hour, .minute, .second], from: date)
            let second = Double(comps.second ?? 0)
            let minute = Double(comps.minute ?? 0) + second / 60
            let hour = Double((comps.hour ?? 0) % 12) + minute / 60

            // Hands (angles measured from 12 o'clock, clockwise).
            context.stroke(handPath(center: center, angle: hour / 12 * 2 * .pi, length: radius * 0.5),
                           with: .color(.white), style: StrokeStyle(lineWidth: max(1.5, radius * 0.09), lineCap: .round))
            context.stroke(handPath(center: center, angle: minute / 60 * 2 * .pi, length: radius * 0.78),
                           with: .color(.white), style: StrokeStyle(lineWidth: max(1, radius * 0.06), lineCap: .round))
            if showSeconds {
                context.stroke(handPath(center: center, angle: second / 60 * 2 * .pi, length: radius * 0.82),
                               with: .color(tint), style: StrokeStyle(lineWidth: max(0.5, radius * 0.03), lineCap: .round))
            }

            // Hub.
            let hub = radius * 0.08
            context.fill(Path(ellipseIn: CGRect(x: center.x - hub, y: center.y - hub,
                                                width: hub * 2, height: hub * 2)),
                         with: .color(tint))
        }
        .contentShape(Rectangle())
    }

    private func point(center: CGPoint, angle: Double, distance: CGFloat) -> CGPoint {
        // angle 0 = straight up; y grows downward in the canvas.
        // Annotate the results as Double so `sin`/`cos` resolve unambiguously — mixing
        // the Double `angle` with the CGFloat `distance` lets the Xcode 26 type-checker
        // see both the Double and CGFloat overloads as equally valid ("ambiguous use of
        // 'sin'"), which broke the build.
        let dx: Double = sin(angle)
        let dy: Double = cos(angle)
        return CGPoint(x: center.x + CGFloat(dx) * distance, y: center.y - CGFloat(dy) * distance)
    }

    private func handPath(center: CGPoint, angle: Double, length: CGFloat) -> Path {
        var path = Path()
        path.move(to: center)
        path.addLine(to: point(center: center, angle: angle, distance: length))
        return path
    }
}
