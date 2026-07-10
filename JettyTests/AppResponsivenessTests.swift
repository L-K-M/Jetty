import XCTest
@testable import Jetty

final class AppResponsivenessTests: XCTestCase {

    func testRepeatedTimeoutsRequireThreeConsecutiveFailures() {
        var count = 0
        count = AppResponsivenessMonitor.nextFailureCount(current: count, outcome: .timedOut)
        XCTAssertEqual(count, 1)
        count = AppResponsivenessMonitor.nextFailureCount(current: count, outcome: .timedOut)
        XCTAssertEqual(count, 2)
        count = AppResponsivenessMonitor.nextFailureCount(current: count, outcome: .timedOut)
        XCTAssertEqual(count, AppResponsivenessMonitor.failuresRequired)
    }

    func testSuccessClearsTimeoutStreakImmediately() {
        let count = AppResponsivenessMonitor.nextFailureCount(
            current: AppResponsivenessMonitor.failuresRequired, outcome: .responsive)
        XCTAssertEqual(count, 0)
    }

    func testUnavailableProbeDoesNotClaimAppIsFrozen() {
        let count = AppResponsivenessMonitor.nextFailureCount(
            current: AppResponsivenessMonitor.failuresRequired - 1, outcome: .unavailable)
        XCTAssertEqual(count, 0)
    }
}
