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

    private static func formatter(template: String, locale: Locale, timeZone: TimeZone) -> DateFormatter {
        let f = DateFormatter()
        f.locale = locale
        f.timeZone = timeZone
        f.setLocalizedDateFormatFromTemplate(template)
        return f
    }
}
