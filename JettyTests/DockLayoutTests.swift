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
        XCTAssertEqual(size.width, 50 + 12 + 50 * 1.6 + 2 * 8 + 2 * 10, accuracy: 0.001)  // 178
        XCTAssertEqual(size.height, 50 + 20, accuracy: 0.001)                            // 70
    }

    func testClockOnlyDockIsWideEnoughNotToClip() {
        let variable = DockLayout.contentSize(tiles: [.clock], iconSize: 50, spacing: 8, padding: 10, edge: .bottom)
        let uniform = DockLayout.contentSize(tileCount: 1, iconSize: 50, spacing: 8, padding: 10, edge: .bottom)
        // The clock is 1.6× wide, so the variable-width panel must be wider than the
        // old uniform assumption (which clipped the clock).
        XCTAssertGreaterThan(variable.width, uniform.width)
        XCTAssertEqual(variable.width, 50 * 1.6 + 20, accuracy: 0.001)                    // 100
    }

    func testVerticalDockWidensAcrossForClock() {
        // On a left/right dock the clock's 1.6× is the *cross* axis (width).
        let size = DockLayout.contentSize(tiles: [.application, .clock],
                                          iconSize: 50, spacing: 8, padding: 10, edge: .left)
        XCTAssertEqual(size.width, 50 * 1.6 + 20, accuracy: 0.001)        // across fits the clock: 100
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

    func testReorderTargetIndex() {
        let step: CGFloat = 60   // icon 52 + spacing 8
        // Drag right ~2 tiles from index 1 -> 3.
        XCTAssertEqual(DockLayout.reorderTargetIndex(currentIndex: 1, translationPrimary: 125, step: step, pinnedCount: 6), 3)
        // Drag left from index 3 -> 1.
        XCTAssertEqual(DockLayout.reorderTargetIndex(currentIndex: 3, translationPrimary: -125, step: step, pinnedCount: 6), 1)
        // Clamps to the ends.
        XCTAssertEqual(DockLayout.reorderTargetIndex(currentIndex: 4, translationPrimary: 9999, step: step, pinnedCount: 6), 5)
        XCTAssertEqual(DockLayout.reorderTargetIndex(currentIndex: 2, translationPrimary: -9999, step: step, pinnedCount: 6), 0)
        // Tiny drag stays put.
        XCTAssertEqual(DockLayout.reorderTargetIndex(currentIndex: 2, translationPrimary: 5, step: step, pinnedCount: 6), 2)
    }
}
