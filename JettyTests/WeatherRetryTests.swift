import XCTest
@testable import Jetty

/// Tests for the weather tile's pure staleness/backoff gate (FAB-B19): a successful
/// fetch stays fresh for 15 minutes, but a *failed* fetch only backs retries off by
/// 60 seconds, so a transient network blip doesn't strand the offline glyph.
final class WeatherRetryTests: XCTestCase {

    private let key = WeatherService.key(latitude: 47.4, longitude: 9.4, celsius: true)
    private let otherKey = WeatherService.key(latitude: 51.5, longitude: -0.1, celsius: true)
    private let now = Date(timeIntervalSince1970: 1_750_000_000)

    private func shouldRefresh(key: String? = nil,
                               lastSuccessKey: String? = nil, lastSuccess: Date? = nil,
                               snapshotKey: String? = nil,
                               lastFailureKey: String? = nil, lastFailure: Date? = nil) -> Bool {
        WeatherService.shouldRefresh(now: now, key: key ?? self.key,
                                     lastSuccessKey: lastSuccessKey, lastSuccess: lastSuccess,
                                     snapshotKey: snapshotKey,
                                     lastFailureKey: lastFailureKey, lastFailure: lastFailure)
    }

    func testNoHistoryRefreshes() {
        XCTAssertTrue(shouldRefresh())
    }

    func testFreshSuccessBlocksRefetch() {
        XCTAssertFalse(shouldRefresh(lastSuccessKey: key,
                                     lastSuccess: now.addingTimeInterval(-5 * 60),
                                     snapshotKey: key))
    }

    func testSuccessExpiresAfterFifteenMinutes() {
        XCTAssertTrue(shouldRefresh(lastSuccessKey: key,
                                    lastSuccess: now.addingTimeInterval(-16 * 60),
                                    snapshotKey: key))
    }

    func testKeyChangeRefetchesDespiteFreshSuccess() {
        // The user moved the location / flipped the unit — the old reading is for the
        // wrong key, so fetch immediately.
        XCTAssertTrue(shouldRefresh(lastSuccessKey: otherKey,
                                    lastSuccess: now.addingTimeInterval(-60),
                                    snapshotKey: otherKey))
    }

    func testFreshSuccessWithoutMatchingSnapshotRefetches() {
        // F-M5: the freshness gate only holds when a snapshot for this key is actually
        // displayable.
        XCTAssertTrue(shouldRefresh(lastSuccessKey: key,
                                    lastSuccess: now.addingTimeInterval(-60),
                                    snapshotKey: otherKey))
    }

    func testRecentFailureBacksOff() {
        XCTAssertFalse(shouldRefresh(lastFailureKey: key,
                                     lastFailure: now.addingTimeInterval(-30)))
    }

    func testFailureRetriesAfterSixtySeconds() {
        XCTAssertTrue(shouldRefresh(lastFailureKey: key,
                                    lastFailure: now.addingTimeInterval(-61)))
    }

    func testFailureForDifferentKeyDoesNotBackOff() {
        // A failure for the old location shouldn't delay fetching the new one.
        XCTAssertTrue(shouldRefresh(lastFailureKey: otherKey,
                                    lastFailure: now.addingTimeInterval(-5)))
    }

    func testFreshSuccessWinsOverStaleFailureRecord() {
        // Belt and braces: a fresh success for this key blocks a refetch even if an
        // old failure stamp lingers.
        XCTAssertFalse(shouldRefresh(lastSuccessKey: key,
                                     lastSuccess: now.addingTimeInterval(-60),
                                     snapshotKey: key,
                                     lastFailureKey: key,
                                     lastFailure: now.addingTimeInterval(-120)))
    }

    func testBackoffIntervalsAreSane() {
        XCTAssertEqual(WeatherService.failureRetryInterval, 60)
        XCTAssertEqual(WeatherService.successRefreshInterval, 15 * 60)
        XCTAssertLessThan(WeatherService.failureRetryInterval, WeatherService.successRefreshInterval)
    }
}
