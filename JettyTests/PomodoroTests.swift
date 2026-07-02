import XCTest
@testable import Jetty

final class PomodoroTests: XCTestCase {

    func testFormatUnderAnHourIsMinutesSeconds() {
        XCTAssertEqual(PomodoroTimer.format(remaining: 25 * 60), "25:00")
        XCTAssertEqual(PomodoroTimer.format(remaining: 90), "1:30")
        XCTAssertEqual(PomodoroTimer.format(remaining: 5), "0:05")
        XCTAssertEqual(PomodoroTimer.format(remaining: 0), "0:00")
    }

    func testFormatPastAnHourIsHoursMinutesSeconds() {
        XCTAssertEqual(PomodoroTimer.format(remaining: 60 * 60), "1:00:00")
        XCTAssertEqual(PomodoroTimer.format(remaining: 90 * 60), "1:30:00")
        // The 180-minute maximum reads clearly instead of an ambiguous "180:00" (M33).
        XCTAssertEqual(PomodoroTimer.format(remaining: 180 * 60), "3:00:00")
    }

    func testFormatClampsNegativeToZero() {
        XCTAssertEqual(PomodoroTimer.format(remaining: -10), "0:00")
    }
}
