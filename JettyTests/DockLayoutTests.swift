import XCTest
import CoreGraphics
@testable import Jetty

final class DockLayoutTests: XCTestCase {

    private let visible = CGRect(x: 0, y: 0, width: 1000, height: 800)

    func testContentSizeHorizontal() {
        let size = DockLayout.contentSize(tileCount: 5, iconSize: 50, spacing: 8, padding: 10, edge: .bottom)
        XCTAssertEqual(size.width, 5 * 50 + 4 * 8 + 20, accuracy: 0.001)   // 302
        XCTAssertEqual(size.height, 50 + 20, accuracy: 0.001)             // 70
    }

    func testContentSizeVerticalSwapsAxes() {
        let h = DockLayout.contentSize(tileCount: 5, iconSize: 50, spacing: 8, padding: 10, edge: .bottom)
        let v = DockLayout.contentSize(tileCount: 5, iconSize: 50, spacing: 8, padding: 10, edge: .left)
        XCTAssertEqual(v.width, h.height, accuracy: 0.001)
        XCTAssertEqual(v.height, h.width, accuracy: 0.001)
    }

    // MARK: Variable-width tiles (BUG-1)

    func testVariableWidthHorizontalSumsActualExtents() {
        // app(50) + horizontal separator(12) + clock(1.6×50=80), 2 gaps, padding.
        let size = DockLayout.contentSize(tiles: [.application, .separator, .clock],
                                          iconSize: 50, spacing: 8, padding: 10, edge: .bottom)
        // Bind to CGFloat so the mixed integer/1.6 literal arithmetic resolves (Xcode 26
        // otherwise flags it "ambiguous" via the CGFloat/Double bridge).
        let expectedWidth: CGFloat = 50 + 12 + 50 * 1.6 + 2 * 8 + 2 * 10   // 178
        XCTAssertEqual(size.width, expectedWidth, accuracy: 0.001)
        XCTAssertEqual(size.height, 50 + 20, accuracy: 0.001)                            // 70
    }

    func testClockOnlyDockIsWideEnoughNotToClip() {
        let variable = DockLayout.contentSize(tiles: [.clock], iconSize: 50, spacing: 8, padding: 10, edge: .bottom)
        let uniform = DockLayout.contentSize(tileCount: 1, iconSize: 50, spacing: 8, padding: 10, edge: .bottom)
        // The clock is 1.6× wide, so the variable-width panel must be wider than the
        // old uniform assumption (which clipped the clock).
        XCTAssertGreaterThan(variable.width, uniform.width)
        let expectedWidth: CGFloat = 50 * 1.6 + 20   // 100
        XCTAssertEqual(variable.width, expectedWidth, accuracy: 0.001)
    }

    func testVerticalDockWidensAcrossForClock() {
        // On a left/right dock the clock's 1.6× is the *cross* axis (width).
        let size = DockLayout.contentSize(tiles: [.application, .clock],
                                          iconSize: 50, spacing: 8, padding: 10, edge: .left)
        let expectedWidth: CGFloat = 50 * 1.6 + 20   // across fits the clock: 100
        XCTAssertEqual(size.width, expectedWidth, accuracy: 0.001)
        XCTAssertEqual(size.height, 50 + 50 + 8 + 20, accuracy: 0.001)    // both tiles are baseSize tall: 128
    }

    func testUniformTilesMatchLegacyCountAPI() {
        let variable = DockLayout.contentSize(tiles: [.application, .application, .file],
                                              iconSize: 50, spacing: 8, padding: 10, edge: .bottom)
        let legacy = DockLayout.contentSize(tileCount: 3, iconSize: 50, spacing: 8, padding: 10, edge: .bottom)
        XCTAssertEqual(variable.width, legacy.width, accuracy: 0.001)
        XCTAssertEqual(variable.height, legacy.height, accuracy: 0.001)
    }

    func testEmptyTilesFallBackToSingleTile() {
        let empty = DockLayout.contentSize(tiles: [], iconSize: 50, spacing: 8, padding: 10, edge: .bottom)
        let one = DockLayout.contentSize(tileCount: 1, iconSize: 50, spacing: 8, padding: 10, edge: .bottom)
        XCTAssertEqual(empty.width, one.width, accuracy: 0.001)
        XCTAssertEqual(empty.height, one.height, accuracy: 0.001)
    }

    func testBottomCenterIsCentered() {
        let anchor = DockAnchor(edge: .bottom, alignment: .center)
        let frame = DockLayout.revealedFrame(anchor: anchor, contentSize: CGSize(width: 302, height: 70), in: visible)
        XCTAssertEqual(frame.minX, (1000 - 302) / 2, accuracy: 0.001)
        XCTAssertEqual(frame.minY, 0, accuracy: 0.001)
    }

    func testBottomTrailingHugsRight() {
        let anchor = DockAnchor(edge: .bottom, alignment: .trailing)
        let frame = DockLayout.revealedFrame(anchor: anchor, contentSize: CGSize(width: 302, height: 70), in: visible)
        XCTAssertEqual(frame.maxX, 1000, accuracy: 0.001)
    }

    func testBottomLeadingHugsLeft() {
        let anchor = DockAnchor(edge: .bottom, alignment: .leading)
        let frame = DockLayout.revealedFrame(anchor: anchor, contentSize: CGSize(width: 302, height: 70), in: visible)
        XCTAssertEqual(frame.minX, 0, accuracy: 0.001)
    }

    func testInsetLiftsOffEdge() {
        let anchor = DockAnchor(edge: .bottom, alignment: .center, inset: 12)
        let frame = DockLayout.revealedFrame(anchor: anchor, contentSize: CGSize(width: 302, height: 70), in: visible)
        XCTAssertEqual(frame.minY, 12, accuracy: 0.001)
    }

    func testOffsetShiftsAndClamps() {
        let shifted = DockLayout.revealedFrame(
            anchor: DockAnchor(edge: .bottom, alignment: .center, offset: 50),
            contentSize: CGSize(width: 302, height: 70), in: visible)
        XCTAssertEqual(shifted.minX, (1000 - 302) / 2 + 50, accuracy: 0.001)

        // A huge offset can't push the dock off-screen.
        let clamped = DockLayout.revealedFrame(
            anchor: DockAnchor(edge: .bottom, alignment: .center, offset: 9999),
            contentSize: CGSize(width: 302, height: 70), in: visible)
        XCTAssertEqual(clamped.maxX, 1000, accuracy: 0.001)
    }

    func testLeftEdgeAlignmentIsVertical() {
        let size = CGSize(width: 70, height: 302)
        let center = DockLayout.revealedFrame(anchor: DockAnchor(edge: .left, alignment: .center), contentSize: size, in: visible)
        XCTAssertEqual(center.minX, 0, accuracy: 0.001)
        XCTAssertEqual(center.minY, (800 - 302) / 2, accuracy: 0.001)

        // leading == top for a vertical dock.
        let leading = DockLayout.revealedFrame(anchor: DockAnchor(edge: .left, alignment: .leading), contentSize: size, in: visible)
        XCTAssertEqual(leading.maxY, 800, accuracy: 0.001)
        let trailing = DockLayout.revealedFrame(anchor: DockAnchor(edge: .left, alignment: .trailing), contentSize: size, in: visible)
        XCTAssertEqual(trailing.minY, 0, accuracy: 0.001)
    }

    func testHiddenFrameSlidesOffKeepingReveal() {
        let revealed = CGRect(x: 349, y: 0, width: 302, height: 70)
        let hidden = DockLayout.hiddenFrame(edge: .bottom, revealedFrame: revealed, in: visible, reveal: 2)
        XCTAssertEqual(hidden.minX, 349, accuracy: 0.001)        // along-edge unchanged
        XCTAssertEqual(hidden.maxY, visible.minY + 2, accuracy: 0.001)  // only 2pt peeks
    }

    func testDefaultHiddenFrameIsFullyOffScreen() {
        // edgeReveal is 0, so the hidden dock shows no pixels.
        let revealed = CGRect(x: 349, y: 0, width: 302, height: 70)
        let hidden = DockLayout.hiddenFrame(edge: .bottom, revealedFrame: revealed, in: visible)
        XCTAssertLessThanOrEqual(hidden.maxY, visible.minY + 0.001)
    }

    func testSlotExtentAlong() {
        // A single app tile = baseSize; a 2-app running group = 2*base + 1*spacing;
        // the clock is 1.6x wide.
        XCTAssertEqual(DockLayout.slotExtentAlong(tileKinds: [.application], baseSize: 50, spacing: 10, edge: .bottom), 50, accuracy: 0.001)
        XCTAssertEqual(DockLayout.slotExtentAlong(tileKinds: [.application, .application], baseSize: 50, spacing: 10, edge: .bottom), 110, accuracy: 0.001)
        XCTAssertEqual(DockLayout.slotExtentAlong(tileKinds: [.clock], baseSize: 50, spacing: 10, edge: .bottom), 80, accuracy: 0.001)
    }

    func testLiveReorderTarget() {
        let extents = Array(repeating: CGFloat(50), count: 6)   // centers: 25,85,145,205,265,325 (spacing 10)
        // Drag slot 1 right ~2 slots -> 3.
        XCTAssertEqual(DockLayout.liveReorderTarget(slotExtents: extents, spacing: 10, draggedIndex: 1, dragAlong: 125), 3)
        // Drag slot 3 left -> 1.
        XCTAssertEqual(DockLayout.liveReorderTarget(slotExtents: extents, spacing: 10, draggedIndex: 3, dragAlong: -125), 1)
        // Clamp to the ends.
        XCTAssertEqual(DockLayout.liveReorderTarget(slotExtents: extents, spacing: 10, draggedIndex: 4, dragAlong: 9999), 5)
        XCTAssertEqual(DockLayout.liveReorderTarget(slotExtents: extents, spacing: 10, draggedIndex: 2, dragAlong: -9999), 0)
        // Tiny drag stays put.
        XCTAssertEqual(DockLayout.liveReorderTarget(slotExtents: extents, spacing: 10, draggedIndex: 2, dragAlong: 5), 2)
    }

    func testLiveReorderTargetWithWideRunningGroup() {
        // A wide running-apps slot (index 2) between single tiles; dragging the last
        // slot left past the wide group lands before it.
        let extents: [CGFloat] = [50, 50, 160, 50]   // centers (spacing 10): 25, 85, 200, 305
        XCTAssertEqual(DockLayout.liveReorderTarget(slotExtents: extents, spacing: 10, draggedIndex: 3, dragAlong: -250), 1)
    }

    // MARK: Edge-crossing reveal (stacked-display seams)

    func testPointerCrossedEdgeBottomSeam() {
        // Upper display A sits directly above another (A.frame.minY == 0); its bottom dock
        // is centred at the physical edge. A pointer that crossed the seam onto the lower
        // display (y just below 0) over the dock's extent counts as an edge slam. Band 24
        // is the live reveal band (a seam doesn't clamp the cursor, so the band is generous).
        let screenA = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let dock = CGRect(x: 400, y: 0, width: 200, height: 70)
        let crossed = { (p: CGPoint) in
            DockLayout.pointerCrossedEdge(p, screenFrame: screenA, dockFrame: dock, edge: .bottom, band: 24, margin: 16)
        }
        XCTAssertTrue(crossed(CGPoint(x: 500, y: -4)))    // just past the seam, over the dock
        XCTAssertTrue(crossed(CGPoint(x: 500, y: -20)))   // overshoot within the 24pt reveal band
        XCTAssertTrue(crossed(CGPoint(x: 610, y: -1)))    // within the along-extent margin (600+16)
        XCTAssertFalse(crossed(CGPoint(x: 500, y: 4)))    // still inside the screen → handled on-screen
        XCTAssertFalse(crossed(CGPoint(x: 500, y: -30)))  // too far past (deep on the other display)
        XCTAssertFalse(crossed(CGPoint(x: 700, y: -4)))   // past the edge but not over the dock
    }

    func testPointerCrossedEdgeHysteresisBand() {
        // Reveal uses band 24, keep-revealed uses band 36, so a point 30pt past the seam is
        // outside the reveal band but inside the keep band — the dock stays up (no flap).
        let screenA = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let dock = CGRect(x: 400, y: 0, width: 200, height: 70)
        let p = CGPoint(x: 500, y: -30)
        XCTAssertFalse(DockLayout.pointerCrossedEdge(p, screenFrame: screenA, dockFrame: dock, edge: .bottom, band: 24, margin: 16))
        XCTAssertTrue(DockLayout.pointerCrossedEdge(p, screenFrame: screenA, dockFrame: dock, edge: .bottom, band: 36, margin: 16))
    }

    func testPointerCrossedEdgeOtherEdges() {
        let screen = CGRect(x: 0, y: 0, width: 1000, height: 800)
        // Top dock: crossing is just ABOVE maxY.
        let topDock = CGRect(x: 400, y: 730, width: 200, height: 70)
        XCTAssertTrue(DockLayout.pointerCrossedEdge(CGPoint(x: 500, y: 810), screenFrame: screen, dockFrame: topDock, edge: .top, band: 24, margin: 16))
        XCTAssertFalse(DockLayout.pointerCrossedEdge(CGPoint(x: 500, y: 796), screenFrame: screen, dockFrame: topDock, edge: .top, band: 24, margin: 16))
        // Right dock: crossing is just RIGHT of maxX.
        let rightDock = CGRect(x: 930, y: 350, width: 70, height: 200)
        XCTAssertTrue(DockLayout.pointerCrossedEdge(CGPoint(x: 1010, y: 450), screenFrame: screen, dockFrame: rightDock, edge: .right, band: 24, margin: 16))
        XCTAssertFalse(DockLayout.pointerCrossedEdge(CGPoint(x: 1010, y: 700), screenFrame: screen, dockFrame: rightDock, edge: .right, band: 24, margin: 16))
    }
}
