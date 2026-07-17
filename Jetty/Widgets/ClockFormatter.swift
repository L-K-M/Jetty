import Foundation

/// Pure date/time formatting for the clock dock tile. Building the strings here
/// (rather than in the SwiftUI view) keeps the format logic unit-testable across
/// 12/24-hour, seconds, weekday, and date options. See PLAN.md §8.1.
enum ClockFormatter {

    struct Lines: Equatable {
        var primary: String      // the time
        var secondary: String?   // the optional date/weekday line
    }

    /// The two lines to show for `date` under the given options. `locale`/`timeZone`
    /// are injectable so tests are deterministic.
    static func lines(for date: Date,
                      use24Hour: Bool,
                      showSeconds: Bool,
                      showDate: Bool,
                      showWeekday: Bool,
                      locale: Locale = .current,
                      timeZone: TimeZone = .current) -> Lines {
        let time = formatter(template: timeTemplate(use24Hour: use24Hour, showSeconds: showSeconds),
                             locale: locale, timeZone: timeZone).string(from: date)

        var dateBits: [String] = []
        if showWeekday {
            dateBits.append(formatter(template: "EEE", locale: locale, timeZone: timeZone).string(from: date))
        }
        if showDate {
            dateBits.append(formatter(template: "MMMd", locale: locale, timeZone: timeZone).string(from: date))
        }
        let secondary = dateBits.isEmpty ? nil : dateBits.joined(separator: "  ")
        return Lines(primary: time, secondary: secondary)
    }

    /// The `DateFormatter` skeleton template for the time portion. Using a localized
    /// template (rather than a fixed pattern) respects regional ordering and the
    /// AM/PM marker placement.
    static func timeTemplate(use24Hour: Bool, showSeconds: Bool) -> String {
        let hour = use24Hour ? "H" : "h"
        let secs = showSeconds ? "ss" : ""
        let ampm = use24Hour ? "" : "a"
        return "\(hour)mm\(secs)\(ampm)"
    }

    /// The hour a digit-based face (the LCD) shows for `hour24` (0–23): unchanged
    /// in 24-hour mode, else folded to 12, 1–11 with an AM/PM marker. Pure.
    static func displayHour(_ hour24: Int, use24Hour: Bool) -> (hour: Int, meridiem: String?) {
        guard !use24Hour else { return (hour24, nil) }
        let folded = hour24 % 12
        return (folded == 0 ? 12 : folded, hour24 < 12 ? "AM" : "PM")
    }

    // MARK: Cached formatters (H14)

    private static let cacheLock = NSLock()
    private static var formatterCache: [String: DateFormatter] = [:]

    /// A `DateFormatter` for `template`/`locale`/`timeZone`, cached by that key.
    /// `DateFormatter` is expensive to build and `lines(for:)` needs up to three per
    /// call — with a 1 Hz `TimelineView` (seconds on) plus per-display world clocks
    /// that was 6+ allocations/second on the main thread. Configured once under a
    /// lock; `DateFormatter.string(from:)` is documented thread-safe for reuse.
    private static func formatter(template: String, locale: Locale, timeZone: TimeZone) -> DateFormatter {
        let key = "\(template)|\(locale.identifier)|\(timeZone.identifier)"
        cacheLock.lock()
        defer { cacheLock.unlock() }
        if let cached = formatterCache[key] { return cached }
        let f = DateFormatter()
        f.locale = locale
        f.timeZone = timeZone
        f.setLocalizedDateFormatFromTemplate(template)
        formatterCache[key] = f
        return f
    }

    // MARK: World-clock day offset

    /// The whole-day difference between a remote zone's calendar day and the local
    /// one at `date`: `+1` when it's already tomorrow there, `-1` when still
    /// yesterday, `nil` when it's the same day. A bare "9:24 Tokyo" actively
    /// misleads when Tokyo is a day ahead. Time zones are injectable so tests are
    /// machine-locale independent. Pure, unit-tested.
    static func dayOffset(for date: Date, remoteTimeZone: TimeZone,
                          localTimeZone: TimeZone = .current) -> Int? {
        func ordinal(in zone: TimeZone) -> Int? {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = zone
            return calendar.ordinality(of: .day, in: .era, for: date)
        }
        guard let local = ordinal(in: localTimeZone), let remote = ordinal(in: remoteTimeZone),
              remote != local else { return nil }
        return remote - local
    }

    // MARK: Minute-cadence alignment (M29)

    /// The start of the minute containing `date`. Used as the phase for a minute-
    /// cadence `TimelineView` so its ticks land on the minute boundary — otherwise
    /// `.periodic(from: .now, by: 60)` ticks 60 s after launch and the displayed
    /// minute lags up to ~60 s behind real time. Pure, unit-tested.
    static func minuteStart(_ date: Date = Date()) -> Date {
        let seconds = date.timeIntervalSinceReferenceDate
        return Date(timeIntervalSinceReferenceDate: (seconds / 60).rounded(.down) * 60)
    }
}
