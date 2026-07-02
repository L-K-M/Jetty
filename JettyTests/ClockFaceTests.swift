import XCTest
@testable import Jetty

final class ClockFaceTests: XCTestCase {

    // MARK: SevenSegment

    func testSegmentCountsMatchTheClassicDisplay() {
        // 0:6, 1:2, 2:5, 3:5, 4:4, 5:5, 6:6, 7:3, 8:7, 9:6 lit segments.
        let counts = [6, 2, 5, 5, 4, 5, 6, 3, 7, 6]
        for digit in 0...9 {
            let segments = SevenSegment.segments(for: digit)
            XCTAssertNotNil(segments, "digit \(digit)")
            XCTAssertEqual(segments?.rawValue.nonzeroBitCount, counts[digit], "digit \(digit)")
        }
    }

    func testEightLightsEverySegmentAndOneOnlyTheRightSide() {
        XCTAssertEqual(SevenSegment.segments(for: 8), .all)
        XCTAssertEqual(SevenSegment.segments(for: 1), [.b, .c])
    }

    func testDigitPatternsAreDistinct() {
        let patterns = (0...9).compactMap { SevenSegment.segments(for: $0)?.rawValue }
        XCTAssertEqual(Set(patterns).count, 10)
    }

    func testOutOfRangeDigitsHaveNoSegments() {
        XCTAssertNil(SevenSegment.segments(for: -1))
        XCTAssertNil(SevenSegment.segments(for: 10))
    }

    // MARK: ClockGeometry

    func testHandAnglesAtThreeOClock() {
        let angles = ClockGeometry.handAngles(hour: 3, minute: 0, second: 0)
        XCTAssertEqual(angles.hour, .pi / 2, accuracy: 1e-9)
        XCTAssertEqual(angles.minute, 0, accuracy: 1e-9)
        XCTAssertEqual(angles.second, 0, accuracy: 1e-9)
    }

    func testHourHandSweepsWithMinutes() {
        // 6:30 → the hour hand sits halfway between 6 and 7.
        let angles = ClockGeometry.handAngles(hour: 6, minute: 30, second: 0)
        XCTAssertEqual(angles.hour, 6.5 / 12 * 2 * .pi, accuracy: 1e-9)
        XCTAssertEqual(angles.minute, .pi, accuracy: 1e-9)
    }

    func testTwentyFourHourClockFoldsOntoTwelve() {
        let evening = ClockGeometry.handAngles(hour: 18, minute: 0, second: 0)
        let morning = ClockGeometry.handAngles(hour: 6, minute: 0, second: 0)
        XCTAssertEqual(evening.hour, morning.hour, accuracy: 1e-9)
    }

    func testPolarPointConvention() {
        // Angle 0 = straight up (negative y in canvas space); π/2 = to the right.
        let up = ClockGeometry.point(center: .zero, angle: 0, distance: 10)
        XCTAssertEqual(up.x, 0, accuracy: 1e-9)
        XCTAssertEqual(up.y, -10, accuracy: 1e-9)
        let right = ClockGeometry.point(center: .zero, angle: .pi / 2, distance: 10)
        XCTAssertEqual(right.x, 10, accuracy: 1e-9)
        XCTAssertEqual(right.y, 0, accuracy: 1e-6)
    }

    // MARK: ClockFormatter.displayHour

    func testDisplayHourTwelveHourFold() {
        XCTAssertEqual(ClockFormatter.displayHour(0, use24Hour: false).hour, 12)
        XCTAssertEqual(ClockFormatter.displayHour(0, use24Hour: false).meridiem, "AM")
        XCTAssertEqual(ClockFormatter.displayHour(12, use24Hour: false).hour, 12)
        XCTAssertEqual(ClockFormatter.displayHour(12, use24Hour: false).meridiem, "PM")
        XCTAssertEqual(ClockFormatter.displayHour(13, use24Hour: false).hour, 1)
        XCTAssertEqual(ClockFormatter.displayHour(23, use24Hour: false).hour, 11)
        XCTAssertEqual(ClockFormatter.displayHour(23, use24Hour: false).meridiem, "PM")
    }

    func testDisplayHourTwentyFourHourPassesThrough() {
        let (hour, meridiem) = ClockFormatter.displayHour(19, use24Hour: true)
        XCTAssertEqual(hour, 19)
        XCTAssertNil(meridiem)
    }

    // MARK: ClockFaceStyle

    func testAnalogFlagPartitionsTheStyles() {
        XCTAssertFalse(ClockFaceStyle.digital.isAnalog)
        XCTAssertFalse(ClockFaceStyle.lcd.isAnalog)
        for style in ClockFaceStyle.allCases where style != .digital && style != .lcd {
            XCTAssertTrue(style.isAnalog, "\(style)")
        }
        for style in ClockFaceStyle.allCases {
            XCTAssertEqual(style.usesTimeDigits, !style.isAnalog, "\(style)")
        }
    }

    func testRawValuesRoundTrip() {
        for style in ClockFaceStyle.allCases {
            XCTAssertEqual(ClockFaceStyle(rawValue: style.rawValue), style)
        }
    }
}
