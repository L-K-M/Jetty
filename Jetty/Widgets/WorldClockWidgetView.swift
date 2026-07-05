import SwiftUI

/// A world-clock tile (ND-3): the time in a chosen time zone plus its short label,
/// ticking via `TimelineView`. Reuses the pure `ClockFormatter` with an injected
/// `TimeZone`, so it honors the user's 12/24-hour and seconds preferences.
struct WorldClockWidgetView: View {
    @ObservedObject var preferences: Preferences
    var height: CGFloat

    // `TimeZone(identifier:)` is not free and the body re-renders every tick,
    // so memoize per identifier (the residual perf nit from H14/L17). Same
    // lock-guarded cache pattern as `ClockFormatter`'s formatter cache; a new
    // preference value is simply a new key.
    private static let zoneCacheLock = NSLock()
    private static var zoneCache: [String: TimeZone] = [:]

    private static func zone(for identifier: String) -> TimeZone {
        zoneCacheLock.lock()
        defer { zoneCacheLock.unlock() }
        if let cached = zoneCache[identifier] { return cached }
        let zone = TimeZone(identifier: identifier) ?? .current
        zoneCache[identifier] = zone
        return zone
    }

    private var timeZone: TimeZone {
        Self.zone(for: preferences.worldClockTimeZone)
    }

    var body: some View {
        // Minute cadence phased to the boundary (M29). Per-second ticks anchor
        // there too — minute starts are second boundaries — so displayed seconds
        // aren't stale by a constant sub-second phase and multiple clock tiles
        // tick in sync (FAB-P2).
        let schedule: PeriodicTimelineSchedule = .periodic(
            from: ClockFormatter.minuteStart(),
            by: preferences.clockShowSeconds ? 1 : 60)
        TimelineView(schedule) { context in
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
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)   // 12-hour + seconds must not wrap/clip (F-L7)
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
