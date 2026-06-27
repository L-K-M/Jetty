import SwiftUI

/// A world-clock tile (ND-3): the time in a chosen time zone plus its short label,
/// ticking via `TimelineView`. Reuses the pure `ClockFormatter` with an injected
/// `TimeZone`, so it honors the user's 12/24-hour and seconds preferences.
struct WorldClockWidgetView: View {
    @ObservedObject var preferences: Preferences
    var height: CGFloat

    private var timeZone: TimeZone {
        TimeZone(identifier: preferences.worldClockTimeZone) ?? .current
    }

    var body: some View {
        let cadence: TimeInterval = preferences.clockShowSeconds ? 1 : 30
        TimelineView(.periodic(from: .now, by: cadence)) { context in
            let lines = ClockFormatter.lines(
                for: context.date,
                use24Hour: preferences.clockUse24Hour,
                showSeconds: preferences.clockShowSeconds,
                showDate: false,
                showWeekday: false,
                timeZone: timeZone)
            VStack(spacing: 1) {
                Text(lines.primary)
                    .font(.system(size: max(11, height * 0.30), weight: .semibold, design: .rounded))
                    .monospacedDigit()
                Text(zoneLabel)
                    .font(.system(size: max(8, height * 0.18), weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 6)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .help(timeZone.identifier)
    }

    /// A compact label: the city portion of the identifier (e.g. "Tokyo" from
    /// "Asia/Tokyo"), with underscores spaced out.
    private var zoneLabel: String {
        let city = timeZone.identifier.split(separator: "/").last.map(String.init) ?? timeZone.identifier
        return city.replacingOccurrences(of: "_", with: " ")
    }
}
