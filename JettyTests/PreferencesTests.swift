import XCTest
@testable import Jetty

final class PreferencesTests: XCTestCase {

    private func freshDefaults() -> UserDefaults {
        let suite = "JettyTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    func testDefaultsApplied() {
        let prefs = Preferences(defaults: freshDefaults())
        XCTAssertEqual(prefs.material, Preferences.Default.material)
        XCTAssertEqual(prefs.edge, .bottom)
        XCTAssertEqual(prefs.iconSize, Preferences.Default.iconSize, accuracy: 0.001)
    }

    func testClampsCorruptStoredValuesOnLoad() {
        let defaults = freshDefaults()
        defaults.set(9999.0, forKey: "iconSize")
        defaults.set(-3.0, forKey: "backgroundOpacity")
        defaults.set(500.0, forKey: "magnification")
        let prefs = Preferences(defaults: defaults)
        XCTAssertEqual(prefs.iconSize, 128, accuracy: 0.001)
        XCTAssertEqual(prefs.backgroundOpacity, 0, accuracy: 0.001)
        XCTAssertEqual(prefs.magnification, 2.5, accuracy: 0.001)
    }

    func testEnumPersistenceRoundTrips() {
        let defaults = freshDefaults()
        let a = Preferences(defaults: defaults)
        a.edge = .right
        a.alignment = .trailing
        a.material = .gradient
        a.indicatorStyle = .bar
        let b = Preferences(defaults: defaults)
        XCTAssertEqual(b.edge, .right)
        XCTAssertEqual(b.alignment, .trailing)
        XCTAssertEqual(b.material, .gradient)
        XCTAssertEqual(b.indicatorStyle, .bar)
    }

    func testApplyPresetUpdatesAppearance() {
        let prefs = Preferences(defaults: freshDefaults())
        let preset = AppearancePreset.builtIns.first { $0.name == "Graphite" }!
        prefs.apply(preset)
        XCTAssertEqual(prefs.material, .solid)
        XCTAssertEqual(prefs.indicatorStyle, .bar)
    }

    func testCaptureThenApplyIsStable() {
        let prefs = Preferences(defaults: freshDefaults())
        prefs.iconSize = 70
        prefs.tintHex = "#112233"
        let captured = prefs.currentAppearancePreset(name: "X")
        let other = Preferences(defaults: freshDefaults())
        other.apply(captured)
        XCTAssertEqual(other.iconSize, 70, accuracy: 0.001)
        XCTAssertEqual(other.tintHex, "#112233")
    }

    func testClockFaceDefaultsToDigitalAndRoundTrips() {
        let defaults = freshDefaults()
        let a = Preferences(defaults: defaults)
        XCTAssertEqual(a.clockFace, .digital)
        a.clockFace = .memphis
        let b = Preferences(defaults: defaults)
        XCTAssertEqual(b.clockFace, .memphis)
    }

    func testClockFaceMigratesFromLegacyAnalogToggle() {
        // An old install with "Analog face" on gets the matching classic dial…
        let defaults = freshDefaults()
        defaults.set(true, forKey: "clockAnalog")
        XCTAssertEqual(Preferences(defaults: defaults).clockFace, .classic)
        // …but a stored face style always wins over the legacy flag.
        defaults.set(ClockFaceStyle.swiss.rawValue, forKey: "clockFace")
        XCTAssertEqual(Preferences(defaults: defaults).clockFace, .swiss)
        // Legacy flag off (or absent) stays digital.
        let plain = freshDefaults()
        plain.set(false, forKey: "clockAnalog")
        XCTAssertEqual(Preferences(defaults: plain).clockFace, .digital)
    }

    func testDefaultAnchorReflectsPosition() {
        let prefs = Preferences(defaults: freshDefaults())
        prefs.edge = .top
        prefs.alignment = .leading
        let anchor = prefs.defaultAnchor(forDisplayUUID: "U")
        XCTAssertEqual(anchor.displayUUID, "U")
        XCTAssertEqual(anchor.edge, .top)
        XCTAssertEqual(anchor.alignment, .leading)
    }
}
