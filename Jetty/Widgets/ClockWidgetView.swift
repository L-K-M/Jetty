import SwiftUI

/// The date/time dock tile (improvement #3). Renders the time in the chosen
/// `ClockFaceStyle` — plain text, a seven-segment LCD, or one of the analog
/// dials (`AnalogClockFace`) — ticking via a `TimelineView` so there are no
/// manual timers. String building lives in the pure `ClockFormatter`. See
/// PLAN.md §8.1.
struct ClockWidgetView: View {
    @ObservedObject var preferences: Preferences
    var height: CGFloat

    var body: some View {
        let face = preferences.clockFace
        // Analog dials tick every second (their minute hand sweeps continuously);
        // text faces tick once a minute unless seconds are shown, phased to the
        // minute boundary so the shown minute never lags up to ~60 s behind (M29).
        let showsSeconds = preferences.clockShowSeconds || face.isAnalog
        let schedule: PeriodicTimelineSchedule = showsSeconds
            ? .periodic(from: .now, by: 1)
            : .periodic(from: ClockFormatter.minuteStart(), by: 60)
        TimelineView(schedule) { context in
            switch face {
            case .digital:
                digital(date: context.date)
            case .lcd:
                LCDClockFace(date: context.date,
                             use24Hour: preferences.clockUse24Hour,
                             showSeconds: preferences.clockShowSeconds)
                    .frame(minWidth: height * 1.4)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .help("Open Calendar")
            default:
                AnalogClockFace(date: context.date,
                                style: face,
                                showSeconds: preferences.clockShowSeconds,
                                tint: preferences.tintColor)
                    .frame(width: height * 0.92, height: height * 0.92)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .help("Open Calendar")
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
