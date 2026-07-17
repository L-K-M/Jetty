import XCTest
@testable import Jetty

final class ClockFormatterTests: XCTestCase {

    private let posix = Locale(identifier: "en_US_POSIX")
    private let gmt = TimeZone(identifier: "GMT")!
    // 1970-01-01 00:00:00 GMT — a Thursday.
    private let epoch = Date(timeIntervalSince1970: 0)

    func test24HourHasColonNoMeridiem() {
        let lines = ClockFormatter.lines(for: epoch, use24Hour: true, showSeconds: false,
                                         showDate: false, showWeekday: false, locale: posix, timeZone: gmt)
        XCTAssertTrue(lines.primary.contains(":"))
        XCTAssertFalse(lines.primary.uppercased().contains("AM"))
        XCTAssertNil(lines.secondary)
    }

    func test12HourHasMeridiem() {
        let lines = ClockFormatter.lines(for: epoch, use24Hour: false, showSeconds: false,
                                         showDate: false, showWeekday: false, locale: posix, timeZone: gmt)
        XCTAssertTrue(lines.primary.uppercased().contains("AM"))
    }

    func testSecondsAddsAnotherColon() {
        let without = ClockFormatter.lines(for: epoch, use24Hour: true, showSeconds: false,
                                           showDate: false, showWeekday: false, locale: posix, timeZone: gmt)
        let with = ClockFormatter.lines(for: epoch, use24Hour: true, showSeconds: true,
                                        showDate: false, showWeekday: false, locale: posix, timeZone: gmt)
        XCTAssertEqual(with.primary.filter { $0 == ":" }.count, without.primary.filter { $0 == ":" }.count + 1)
    }

    func testSecondaryShowsWeekdayAndDate() {
        let lines = ClockFormatter.lines(for: epoch, use24Hour: true, showSeconds: false,
                                         showDate: true, showWeekday: true, locale: posix, timeZone: gmt)
        XCTAssertNotNil(lines.secondary)
        XCTAssertTrue(lines.secondary?.contains("Thu") ?? false)
        XCTAssertTrue(lines.secondary?.contains("Jan") ?? false)
    }

    func testNoSecondaryWhenBothOff() {
        let lines = ClockFormatter.lines(for: epoch, use24Hour: true, showSeconds: false,
                                         showDate: false, showWeekday: false, locale: posix, timeZone: gmt)
        XCTAssertNil(lines.secondary)
    }

    func testMinuteStartFloorsToTheMinute() {
        // 100.7 s past the epoch → floors to 60 s (minute 1), dropping the 40.7 s.
        let date = Date(timeIntervalSince1970: 100.7)
        let start = ClockFormatter.minuteStart(date)
        XCTAssertEqual(start.timeIntervalSince1970, 60, accuracy: 0.0001)
        // Already on a boundary → unchanged.
        let onBoundary = Date(timeIntervalSince1970: 120)
        XCTAssertEqual(ClockFormatter.minuteStart(onBoundary).timeIntervalSince1970, 120, accuracy: 0.0001)
        // Result is never in the future relative to its input.
        XCTAssertLessThanOrEqual(start.timeIntervalSince1970, date.timeIntervalSince1970)
    }

    func testWorldClockDayOffset() {
        let utc = TimeZone(identifier: "UTC")!
        let auckland = TimeZone(identifier: "Pacific/Auckland")!   // UTC+12/+13
        let la = TimeZone(identifier: "America/Los_Angeles")!      // UTC-7/-8
        // 2026-01-01 12:00 UTC → already Jan 2 in Auckland, same day in LA.
        let noonUTC = Date(timeIntervalSince1970: 1_767_268_800)
        XCTAssertEqual(ClockFormatter.dayOffset(for: noonUTC, remoteTimeZone: auckland, localTimeZone: utc), 1)
        XCTAssertNil(ClockFormatter.dayOffset(for: noonUTC, remoteTimeZone: la, localTimeZone: utc))
        // 2026-01-01 01:00 UTC → still Dec 31 in LA.
        let earlyUTC = Date(timeIntervalSince1970: 1_767_229_200)
        XCTAssertEqual(ClockFormatter.dayOffset(for: earlyUTC, remoteTimeZone: la, localTimeZone: utc), -1)
        XCTAssertNil(ClockFormatter.dayOffset(for: earlyUTC, remoteTimeZone: utc, localTimeZone: utc))
    }
}
