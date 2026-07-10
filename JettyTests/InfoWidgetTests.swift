import XCTest
@testable import Jetty

final class InfoWidgetTests: XCTestCase {

    // MARK: Battery

    func testBatteryPercentClamps() {
        XCTAssertEqual(SystemStats.clampPercent(-5), 0)
        XCTAssertEqual(SystemStats.clampPercent(150), 100)
        XCTAssertEqual(SystemStats.clampPercent(73), 73)
    }

    func testBatterySymbolByLevel() {
        // The glyph reflects the level regardless of charging — a 5% battery on the
        // charger no longer shows a full-battery glyph (M30). Charging is a bolt overlay.
        XCTAssertEqual(SystemStats.batterySymbol(percent: 5), "battery.0")
        XCTAssertEqual(SystemStats.batterySymbol(percent: 30), "battery.25")
        XCTAssertEqual(SystemStats.batterySymbol(percent: 55), "battery.50")
        XCTAssertEqual(SystemStats.batterySymbol(percent: 80), "battery.75")
        XCTAssertEqual(SystemStats.batterySymbol(percent: 100), "battery.100")
    }

    func testLowBatteryOnlyWhenUnpluggedAndUnder20() {
        XCTAssertTrue(SystemStats.isLowBattery(percent: 15, isPlugged: false))
        XCTAssertFalse(SystemStats.isLowBattery(percent: 15, isPlugged: true))   // on AC → no warning
        XCTAssertFalse(SystemStats.isLowBattery(percent: 25, isPlugged: false))  // above threshold
    }

    // MARK: Weather

    func testWeatherSymbolMapping() {
        XCTAssertEqual(WeatherService.symbol(forCode: 0), "sun.max.fill")
        XCTAssertEqual(WeatherService.symbol(forCode: 2), "cloud.sun.fill")
        XCTAssertEqual(WeatherService.symbol(forCode: 65), "cloud.rain.fill")
        XCTAssertEqual(WeatherService.symbol(forCode: 96), "cloud.bolt.rain.fill")
        XCTAssertEqual(WeatherService.symbol(forCode: 12345), "cloud.fill")
    }

    func testWeatherParseValidPayload() {
        let json = """
        { "current": { "temperature_2m": 21.4, "weather_code": 3 } }
        """.data(using: .utf8)
        let snap = WeatherService.parse(json, celsius: true)
        XCTAssertEqual(snap?.temperature, 21.4)
        XCTAssertEqual(snap?.code, 3)
        XCTAssertEqual(snap?.celsius, true)
    }

    func testWeatherParseCarriesRequestKey() {
        let json = """
        { "current": { "temperature_2m": 21.4, "weather_code": 3 } }
        """.data(using: .utf8)
        let snap = WeatherService.parse(json, celsius: false, key: "51,-0.1,false")
        XCTAssertEqual(snap?.key, "51,-0.1,false")
    }

    func testWeatherParseRejectsGarbage() {
        XCTAssertNil(WeatherService.parse(nil, celsius: true))
        XCTAssertNil(WeatherService.parse(Data("not json".utf8), celsius: true))
        XCTAssertNil(WeatherService.parse(Data("{}".utf8), celsius: true))
    }

    // MARK: Now playing

    func testNowPlayingParsePlaying() {
        let info: [String: Any] = [
            "kMRMediaRemoteNowPlayingInfoTitle": "Lateralus",
            "kMRMediaRemoteNowPlayingInfoArtist": "Tool",
            "kMRMediaRemoteNowPlayingInfoPlaybackRate": NSNumber(value: 1.0),
        ]
        let snap = NowPlayingService.parse(info)
        XCTAssertEqual(snap?.title, "Lateralus")
        XCTAssertEqual(snap?.artist, "Tool")
        XCTAssertEqual(snap?.isPlaying, true)
    }

    func testNowPlayingParsePausedAndMissingArtist() {
        let info: [String: Any] = [
            "kMRMediaRemoteNowPlayingInfoTitle": "Untitled",
            "kMRMediaRemoteNowPlayingInfoPlaybackRate": NSNumber(value: 0.0),
        ]
        let snap = NowPlayingService.parse(info)
        XCTAssertEqual(snap?.title, "Untitled")
        XCTAssertNil(snap?.artist)
        XCTAssertEqual(snap?.isPlaying, false)
    }

    func testNowPlayingParseRejectsEmpty() {
        XCTAssertNil(NowPlayingService.parse(nil))
        XCTAssertNil(NowPlayingService.parse([:]))
        XCTAssertNil(NowPlayingService.parse(["kMRMediaRemoteNowPlayingInfoTitle": ""]))
    }

    // MARK: System Monitor graph

    func testNetworkThroughputDifferencesCounters() {
        let rate = LiveSystemStats.throughput(current: (received: 10_000, sent: 2_000),
                                              previous: (received: 8_000, sent: 1_500),
                                              interval: 2)
        XCTAssertEqual(rate.down, 1_000, accuracy: 0.001)   // (10000-8000)/2
        XCTAssertEqual(rate.up, 250, accuracy: 0.001)       // (2000-1500)/2
    }

    func testNetworkThroughputUsesActualElapsedTime() {
        let rate = LiveSystemStats.throughput(current: (received: 12_000, sent: 5_000),
                                              previous: (received: 8_000, sent: 1_000),
                                              interval: 4)
        XCTAssertEqual(rate.down, 1_000, accuracy: 0.001)
        XCTAssertEqual(rate.up, 1_000, accuracy: 0.001)
    }

    func testNetworkThroughputHandlesNoPreviousAndCounterReset() {
        // No baseline yet → no rate (avoids a spike on first sample / after restart).
        let first = LiveSystemStats.throughput(current: (received: 5_000, sent: 5_000),
                                               previous: nil, interval: 2)
        XCTAssertEqual(first.down, 0)
        XCTAssertEqual(first.up, 0)
        // Counter went backwards (32-bit wrap / interface reset) → clamp to 0, never negative.
        let reset = LiveSystemStats.throughput(current: (received: 100, sent: 100),
                                               previous: (received: 9_000, sent: 9_000),
                                               interval: 2)
        XCTAssertEqual(reset.down, 0)
        XCTAssertEqual(reset.up, 0)
    }

    func testHistoryRingBufferCaps() {
        var history: [SystemSample] = []
        for i in 0..<10 {
            history = LiveSystemStats.appending(SystemSample(load: Double(i), memory: 0, netDown: 0, netUp: 0),
                                                to: history, cap: 4)
        }
        XCTAssertEqual(history.count, 4)
        XCTAssertEqual(history.map(\.load), [6, 7, 8, 9])   // oldest trimmed, newest kept in order
    }

    func testLongSamplingGapThreshold() {
        XCTAssertFalse(LiveSystemStats.isLongSamplingGap(elapsed: 5.9, expected: 2))
        XCTAssertTrue(LiveSystemStats.isLongSamplingGap(elapsed: 6, expected: 2))
        XCTAssertTrue(LiveSystemStats.isLongSamplingGap(elapsed: .nan, expected: 2))
        XCTAssertTrue(LiveSystemStats.isLongSamplingGap(elapsed: -1, expected: 2))
        XCTAssertTrue(LiveSystemStats.isLongSamplingGap(elapsed: 2, expected: 0))
    }

    func testGraphAutoScaleUsesFloorWhenQuiet() {
        // All values below the floor → scaled against the floor (a low, flat trace), not
        // amplified to full height.
        let scaled = SystemMonitorGraph.autoScaled([1024, 2048], floor: SystemMonitorGraph.netFloor)
        XCTAssertLessThan(scaled.max() ?? 1, 0.1)
        // A value above the floor scales against the real max (peak hits 1.0).
        let busy = SystemMonitorGraph.autoScaled([0, 500_000, 1_000_000], floor: SystemMonitorGraph.netFloor)
        XCTAssertEqual(busy.last ?? 0, 1.0, accuracy: 0.001)
        XCTAssertEqual(busy.first ?? -1, 0.0, accuracy: 0.001)
    }

    func testGraphRateFormatting() {
        XCTAssertEqual(SystemMonitorGraph.formatRate(0), "0")
        // A trickle below 1 KiB/s reads as "<1K", not a hard zero (FAB-V7)…
        XCTAssertEqual(SystemMonitorGraph.formatRate(1), "<1K")
        XCTAssertEqual(SystemMonitorGraph.formatRate(512), "<1K")
        XCTAssertEqual(SystemMonitorGraph.formatRate(1023), "<1K")
        // …negative rates still clamp to true silence.
        XCTAssertEqual(SystemMonitorGraph.formatRate(-100), "0")
        XCTAssertEqual(SystemMonitorGraph.formatRate(1024), "1K")
        XCTAssertEqual(SystemMonitorGraph.formatRate(64 * 1024), "64K")
        XCTAssertEqual(SystemMonitorGraph.formatRate(2 * 1024 * 1024), "2.0M")
    }

    func testGraphWhiteLiftOnlyForDarkColors() {
        // Bright series colors keep their exact hue/brightness…
        XCTAssertEqual(SystemMonitorGraph.whiteLift(forLuminance: 0.9), 0, accuracy: 0.0001)
        XCTAssertEqual(SystemMonitorGraph.whiteLift(forLuminance: 0.35), 0, accuracy: 0.0001)
        // …dark ones get lifted toward white so they read on the dark plate.
        XCTAssertEqual(SystemMonitorGraph.whiteLift(forLuminance: 0.1), 0.55, accuracy: 0.0001)
        XCTAssertEqual(SystemMonitorGraph.whiteLift(forLuminance: 0), 0.55, accuracy: 0.0001)
    }

    func testLEDSegmentsRoundAndClamp() {
        XCTAssertEqual(SystemMonitorGraph.litSegments(value: 0, count: 8), 0)
        XCTAssertEqual(SystemMonitorGraph.litSegments(value: 1, count: 8), 8)
        XCTAssertEqual(SystemMonitorGraph.litSegments(value: 0.5, count: 8), 4)
        XCTAssertEqual(SystemMonitorGraph.litSegments(value: 2.0, count: 8), 8)   // clamped
        XCTAssertEqual(SystemMonitorGraph.litSegments(value: -1, count: 8), 0)    // clamped
        XCTAssertEqual(SystemMonitorGraph.litSegments(value: 0.5, count: 0), 0)   // degenerate
    }

    func testLEDSegmentsLightTheBottomSegmentForAnyNonzeroValue() {
        // Rounding alone left an idle machine (< 6.25% on 8 segments) with dead
        // columns; any nonzero load now lights at least the bottom LED (FAB-V7)…
        XCTAssertEqual(SystemMonitorGraph.litSegments(value: 0.01, count: 8), 1)
        XCTAssertEqual(SystemMonitorGraph.litSegments(value: 0.06, count: 8), 1)
        XCTAssertEqual(SystemMonitorGraph.litSegments(value: 0.001, count: 8), 1)
        // …values past the rounding threshold are unaffected by the floor…
        XCTAssertEqual(SystemMonitorGraph.litSegments(value: 0.07, count: 8), 1)  // rounds to 1 anyway
        XCTAssertEqual(SystemMonitorGraph.litSegments(value: 0.13, count: 8), 1)
        XCTAssertEqual(SystemMonitorGraph.litSegments(value: 0.25, count: 8), 2)
        // …and exact zero (or negative, clamped to zero) stays fully dark.
        XCTAssertEqual(SystemMonitorGraph.litSegments(value: 0, count: 8), 0)
        XCTAssertEqual(SystemMonitorGraph.litSegments(value: -0.5, count: 8), 0)
        XCTAssertEqual(SystemMonitorGraph.litSegments(value: 0.01, count: 0), 0)  // degenerate count
    }

    func testLEDZonesMatchTheBarThresholds() {
        // 8-segment column: centers at 6.25%, 18.75%, … — green below 60%,
        // amber to 85%, red above.
        XCTAssertEqual(SystemMonitorGraph.ledZone(index: 0, count: 8), .green)
        XCTAssertEqual(SystemMonitorGraph.ledZone(index: 4, count: 8), .green)   // 56.25%
        XCTAssertEqual(SystemMonitorGraph.ledZone(index: 5, count: 8), .amber)   // 68.75%
        XCTAssertEqual(SystemMonitorGraph.ledZone(index: 6, count: 8), .amber)   // 81.25%
        XCTAssertEqual(SystemMonitorGraph.ledZone(index: 7, count: 8), .red)     // 93.75%
    }

    func testGaugeAngleSweep() {
        // ±60° sweep centered on 12 o'clock, clamped outside 0…1.
        XCTAssertEqual(SystemMonitorGraph.gaugeAngle(0), -.pi / 3, accuracy: 1e-9)
        XCTAssertEqual(SystemMonitorGraph.gaugeAngle(0.5), 0, accuracy: 1e-9)
        XCTAssertEqual(SystemMonitorGraph.gaugeAngle(1), .pi / 3, accuracy: 1e-9)
        XCTAssertEqual(SystemMonitorGraph.gaugeAngle(7), .pi / 3, accuracy: 1e-9)
    }

    // MARK: Tile geometry

    func testWideWidgetsAreWiderThanSquareTiles() {
        XCTAssertGreaterThan(DockItemKind.worldClock.tileWidthFactor, 1.0)
        XCTAssertGreaterThan(DockItemKind.weather.tileWidthFactor, 1.0)
        XCTAssertEqual(DockItemKind.application.tileWidthFactor, 1.0)
    }
}
