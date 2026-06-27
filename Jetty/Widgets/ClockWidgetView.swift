import SwiftUI

/// The date/time dock tile (improvement #3). Renders the time and, optionally, the
/// date/weekday, ticking via a `TimelineView` so there are no manual timers. The
/// string building lives in the pure `ClockFormatter`. See PLAN.md §8.1.
struct ClockWidgetView: View {
    @ObservedObject var preferences: Preferences
    var height: CGFloat

    var body: some View {
        let cadence: TimeInterval = preferences.clockShowSeconds ? 1 : 30
        TimelineView(.periodic(from: .now, by: cadence)) { context in
            let lines = ClockFormatter.lines(
                for: context.date,
                use24Hour: preferences.clockUse24Hour,
                showSeconds: preferences.clockShowSeconds,
                showDate: preferences.clockShowDate,
                showWeekday: preferences.clockShowWeekday)

            VStack(spacing: 1) {
                Text(lines.primary)
                    .font(.system(size: max(11, height * 0.32), weight: .semibold, design: .rounded))
                    .monospacedDigit()
                if let secondary = lines.secondary {
                    Text(secondary)
                        .font(.system(size: max(8, height * 0.2), weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 8)
            .frame(minWidth: height * 1.4)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .help("Open Calendar")
        }
    }
}
