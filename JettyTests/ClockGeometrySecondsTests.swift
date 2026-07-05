import XCTest
@testable import Jetty

/// `ClockGeometry.handAngles` with nonzero seconds (FAB-T2 #4): the minute
/// hand sweeps continuously with the seconds (and the hour hand with the
/// minutes), and the second angle itself is correct. Angles are radians,
/// clockwise from 12 o'clock.
final class ClockGeometrySecondsTests: XCTestCase {

    func testMinuteHandAdvancesWithSeconds() {
        // At 0:00:30 half a minute has passed: the minute hand sits half a
        // tick past 12 (one tick = 2π/60), and the hour hand creeps too.
        let angles = ClockGeometry.handAngles(hour: 0, minute: 0, second: 30)
        XCTAssertEqual(angles.minute, .pi / 60, accuracy: 1e-9)
        XCTAssertEqual(angles.second, .pi, accuracy: 1e-9)      // 30s = half the dial
        XCTAssertEqual(angles.hour, .pi / 720, accuracy: 1e-9)  // 0.5min of 720 in 12h
    }

    func testSecondAngleQuarters() {
        XCTAssertEqual(ClockGeometry.handAngles(hour: 0, minute: 0, second: 0).second, 0, accuracy: 1e-9)
        XCTAssertEqual(ClockGeometry.handAngles(hour: 0, minute: 0, second: 15).second, .pi / 2, accuracy: 1e-9)
        XCTAssertEqual(ClockGeometry.handAngles(hour: 0, minute: 0, second: 45).second, 3 * .pi / 2, accuracy: 1e-9)
    }

    func testMinuteHandSweepIsContinuousAcrossTheMinuteTick() {
        // 10:09:59 is exactly one second of sweep (2π/3600) shy of 10:10:00,
        // so the hand glides through the tick instead of jumping.
        let before = ClockGeometry.handAngles(hour: 10, minute: 9, second: 59)
        let after = ClockGeometry.handAngles(hour: 10, minute: 10, second: 0)
        XCTAssertLessThan(before.minute, after.minute)
        XCTAssertEqual(after.minute - before.minute, 2 * .pi / 3600, accuracy: 1e-9)
        XCTAssertEqual(after.minute, 10.0 / 60 * 2 * .pi, accuracy: 1e-9)
    }

    func testSecondsFeedTheHourHandThroughTheMinutes() {
        // At 6:30:45 the minute hand is at 30.75 minutes and the hour hand at
        // 6 + 30.75/60 hours.
        let angles = ClockGeometry.handAngles(hour: 6, minute: 30, second: 45)
        XCTAssertEqual(angles.minute, 30.75 / 60 * 2 * .pi, accuracy: 1e-9)
        XCTAssertEqual(angles.hour, (6 + 30.75 / 60) / 12 * 2 * .pi, accuracy: 1e-9)
        XCTAssertEqual(angles.second, 3 * .pi / 2, accuracy: 1e-9)
    }
}
