import XCTest
import CoreGraphics
@testable import Jetty

/// Gap-filling coverage (FAB-T2 #2 & #3): the `.left` branch of the
/// edge-crossing reveal (the other three edges are tested in
/// `DockLayoutTests`; four-way switches are the classic copy-paste failure
/// mode), and the `Preferences.effectiveClockZoom` gate that turns the whole
/// face-zoom pipeline on/off.
final class DockLayoutGapTests: XCTestCase {

    // MARK: pointerCrossedEdge — left edge

    func testPointerCrossedEdgeLeftSeam() {
        // A left dock centred on the screen's left edge; crossing is just LEFT of minX.
        let screen = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let leftDock = CGRect(x: 0, y: 350, width: 70, height: 200)
        let crossed = { (p: CGPoint) in
            DockLayout.pointerCrossedEdge(p, screenFrame: screen, dockFrame: leftDock, edge: .left, band: 24, margin: 16)
        }
        XCTAssertTrue(crossed(CGPoint(x: -4, y: 450)))    // just past the seam, over the dock
        XCTAssertTrue(crossed(CGPoint(x: -20, y: 450)))   // overshoot within the 24pt band
        XCTAssertTrue(crossed(CGPoint(x: -1, y: 340)))    // within the along-extent margin (350-16)
        XCTAssertFalse(crossed(CGPoint(x: 4, y: 450)))    // still inside the screen → handled on-screen
        XCTAssertFalse(crossed(CGPoint(x: -30, y: 450)))  // too far past the band
        XCTAssertFalse(crossed(CGPoint(x: -4, y: 600)))   // past the edge but not over the dock (550+16)
    }

    // MARK: Preferences.effectiveClockZoom

    private func freshDefaults() -> UserDefaults {
        let suite = "JettyTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        return defaults
    }

    func testEffectiveClockZoomIsUnityForTheDigitalFace() {
        let prefs = Preferences(defaults: freshDefaults())
        prefs.clockFace = .digital
        prefs.clockFaceZoom = 1.8
        XCTAssertEqual(prefs.effectiveClockZoom, 1.0, accuracy: 0.001)
    }

    func testEffectiveClockZoomPassesStoredZoomThroughForAnalogFaces() {
        let prefs = Preferences(defaults: freshDefaults())
        prefs.clockFaceZoom = 1.8
        prefs.clockFace = .classic
        XCTAssertEqual(prefs.effectiveClockZoom, 1.8, accuracy: 0.001)
        prefs.clockFace = .memphis
        XCTAssertEqual(prefs.effectiveClockZoom, 1.8, accuracy: 0.001)
    }

    func testEffectiveClockZoomFollowsFaceSwitches() {
        // Toggling to digital gates the zoom off without losing the stored value.
        let prefs = Preferences(defaults: freshDefaults())
        prefs.clockFace = .classic
        prefs.clockFaceZoom = 2.5
        XCTAssertEqual(prefs.effectiveClockZoom, 2.5, accuracy: 0.001)
        prefs.clockFace = .digital
        XCTAssertEqual(prefs.effectiveClockZoom, 1.0, accuracy: 0.001)
        XCTAssertEqual(prefs.clockFaceZoom, 2.5, accuracy: 0.001)
        prefs.clockFace = .classic
        XCTAssertEqual(prefs.effectiveClockZoom, 2.5, accuracy: 0.001)
    }
}
