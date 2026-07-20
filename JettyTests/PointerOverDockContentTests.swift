import XCTest
@testable import Jetty

/// `DockLayout.pointerOverDockContent` — the geometric replacement for the keep-area
/// view hit-test. It must say **yes** over the strip-anchored tiles at their current
/// hover-magnified extents (so riding a magnified icon into the transparent headroom
/// keeps the dock up) and **no** in empty headroom (so the panel's bounding box —
/// magnification / clock-zoom / label room — never re-inflates the hide distance).
final class PointerOverDockContentTests: XCTestCase {

    // Five square app tiles on a bottom dock: icon 64, spacing 8, padding 10.
    // Content along = 5·64 + 4·8 + 2·10 = 372. With magnification 2 the panel is
    // 372 + 64 = 436 along and 64 + 20 + 64 = 148 across; the slot stack leads at
    // (436 − 372)/2 + 10 = 42, so tile centers sit at x = 74, 146, 218, 290, 362.
    private let apps: [DockItemKind] = [.application, .application, .application,
                                        .application, .application]
    private let panel = CGSize(width: 436, height: 148)

    private func overContent(_ point: CGPoint, panelSize: CGSize? = nil,
                             tiles: [DockItemKind]? = nil, edge: DockEdge = .bottom,
                             magnification: CGFloat = 2, clockWidthFactor: CGFloat = 1.6,
                             clockZoom: CGFloat = 1, spacing: CGFloat = 8,
                             slop: CGFloat = 0) -> Bool {
        DockLayout.pointerOverDockContent(point: point, panelSize: panelSize ?? panel,
                                          edge: edge, tiles: tiles ?? apps, iconSize: 64,
                                          spacing: spacing, padding: 10,
                                          magnification: magnification,
                                          clockWidthFactor: clockWidthFactor,
                                          clockZoom: clockZoom, slop: slop)
    }

    func testEmptyHeadroomIsNotContent() {
        // The reported bug: pointer high in the panel's transparent headroom, hide
        // distance 0 — the dock must be allowed to hide. Even directly above a fully
        // magnified tile (top of icon = 64 × 2 = 128), the panel top is empty.
        XCTAssertFalse(overContent(CGPoint(x: 218, y: 147)))
        // Off the stack's leading end, above the reach of the part-magnified end tile.
        XCTAssertFalse(overContent(CGPoint(x: 30, y: 140)))
    }

    func testMagnifiedTileTopIsContent() {
        // Directly over the middle tile's center the scale is the full 2×, so the
        // icon really renders up to y = 128: just below is content, just above isn't.
        XCTAssertTrue(overContent(CGPoint(x: 218, y: 120)))
        XCTAssertFalse(overContent(CGPoint(x: 218, y: 135)))
    }

    func testMagnificationOffLimitsContentToRestingIcons() {
        // Magnification disabled (peak scale 1): the panel keeps label headroom, but
        // tiles only render to their resting 64 — the stack leads at 10, centers at
        // x = 42…330. Over an icon is content; the label headroom above it is not.
        let restingPanel = CGSize(width: 372, height: 148)
        XCTAssertTrue(overContent(CGPoint(x: 186, y: 60), panelSize: restingPanel,
                                  magnification: 1))
        XCTAssertFalse(overContent(CGPoint(x: 186, y: 100), panelSize: restingPanel,
                                   magnification: 1))
    }

    func testSlopGrowsTheTileEnvelope() {
        // Hide distance grows each tile's envelope like it grows the strip: 140 is
        // 12 past the magnified icon top (128), so slop 20 keeps it, slop 5 doesn't.
        XCTAssertTrue(overContent(CGPoint(x: 218, y: 140), slop: 20))
        XCTAssertFalse(overContent(CGPoint(x: 218, y: 140), slop: 5))
    }

    func testWideGapBetweenTilesIsNotContent() {
        // Two tiles 200 apart (content along = 348, panel = 412, centers x = 74/338):
        // midway between them, above the strip, neither part-magnified icon reaches.
        let gapped: [DockItemKind] = [.application, .application]
        XCTAssertFalse(overContent(CGPoint(x: 206, y: 100),
                                   panelSize: CGSize(width: 412, height: 148),
                                   tiles: gapped, spacing: 200))
    }

    func testVerticalDockMapsAlongFromTheTop() {
        // Left dock, three tiles (content along = 228, panel height = 292): the stack
        // leads 42 from the *top*, so tile 0's center is at y = 292 − 74 = 218. The
        // magnified icon reaches x = 128 out from the left edge.
        let vertical = CGSize(width: 148, height: 292)
        let three: [DockItemKind] = [.application, .application, .application]
        XCTAssertTrue(overContent(CGPoint(x: 120, y: 218), panelSize: vertical,
                                  tiles: three, edge: .left))
        XCTAssertFalse(overContent(CGPoint(x: 135, y: 218), panelSize: vertical,
                                   tiles: three, edge: .left))
        // Last tile sits at the stack's low end: y = 292 − 218 = 74.
        XCTAssertTrue(overContent(CGPoint(x: 60, y: 74), panelSize: vertical,
                                  tiles: three, edge: .left))
    }

    func testZoomedClockFaceCountsAsContentWhereAppIconsDoNot() {
        // App + classic clock zoomed 3× (width factor max(1.6, 0.92·3 + 0.08) = 2.84):
        // content along = 64 + 181.76 + 8 + 20 = 273.76, panel = 455.52 along and
        // 84 + clockZoomHeadroom(64, 10, 3, 2) = 399.12 across; stack leads at 100.88,
        // so the app centers at x = 132.88 and the clock at x = 263.76. The zoomed,
        // magnified face renders up to 64 · 3.04 · 2 = 389.12 across — y = 350 over
        // the clock is content; the same height over the app tile is empty headroom.
        let kinds: [DockItemKind] = [.application, .clock]
        let clockPanel = CGSize(width: 455.52, height: 399.12)
        let factor = DockLayout.clockTileWidthFactor(zoom: 3, face: .classic)
        XCTAssertTrue(overContent(CGPoint(x: 263.76, y: 350), panelSize: clockPanel,
                                  tiles: kinds, clockWidthFactor: factor, clockZoom: 3))
        XCTAssertFalse(overContent(CGPoint(x: 132.88, y: 350), panelSize: clockPanel,
                                   tiles: kinds, clockWidthFactor: factor, clockZoom: 3))
    }

    func testOverflowingContentFallsBackToStripOnly() {
        // Panel shorter than the natural content along-size → the overflow-scroll
        // state: magnification is suspended and nothing renders past the strip, so no
        // point counts as content (the strip region is checked by the caller).
        XCTAssertFalse(overContent(CGPoint(x: 150, y: 100),
                                   panelSize: CGSize(width: 300, height: 148)))
        XCTAssertFalse(overContent(CGPoint(x: 150, y: 60),
                                   panelSize: CGSize(width: 300, height: 148)))
    }
}
