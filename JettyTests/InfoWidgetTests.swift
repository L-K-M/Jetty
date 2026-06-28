import XCTest
@testable import Jetty

final class InfoWidgetTests: XCTestCase {

    // MARK: Battery

    func testBatteryPercentClamps() {
        XCTAssertEqual(SystemStats.clampPercent(-5), 0)
        XCTAssertEqual(SystemStats.clampPercent(150), 100)
        XCTAssertEqual(SystemStats.clampPercent(73), 73)
    }

    func testBatterySymbolByLevelAndCharging() {
        XCTAssertEqual(SystemStats.batterySymbol(percent: 50, isCharging: true), "battery.100.bolt")
        XCTAssertEqual(SystemStats.batterySymbol(percent: 5, isCharging: false), "battery.0")
        XCTAssertEqual(SystemStats.batterySymbol(percent: 100, isCharging: false), "battery.100")
        XCTAssertEqual(SystemStats.batterySymbol(percent: 55, isCharging: false), "battery.50")
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
        XCTAssertEqual(SystemMonitorGraph.formatRate(512), "0")
        XCTAssertEqual(SystemMonitorGraph.formatRate(64 * 1024), "64K")
        XCTAssertEqual(SystemMonitorGraph.formatRate(2 * 1024 * 1024), "2.0M")
    }

    // MARK: Tile geometry

    func testWideWidgetsAreWiderThanSquareTiles() {
        XCTAssertGreaterThan(DockItemKind.worldClock.tileWidthFactor, 1.0)
        XCTAssertGreaterThan(DockItemKind.weather.tileWidthFactor, 1.0)
        XCTAssertEqual(DockItemKind.application.tileWidthFactor, 1.0)
    }
}
