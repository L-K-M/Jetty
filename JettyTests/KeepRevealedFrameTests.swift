import XCTest
@testable import Jetty

/// `DockLayout.keepRevealedFrame` — the pointer region that keeps a revealed dock up:
/// the revealed frame grown by the hide-distance slop and extended across any inset
/// gap to the physical screen edge (where the hard-edge reveal would instantly
/// re-fire, so hiding there would flap).
final class KeepRevealedFrameTests: XCTestCase {

    private let screen = CGRect(x: 0, y: 0, width: 1600, height: 1000)

    func testFlushDockIsJustTheSlopInset() {
        // Dock touching the physical edge (inset 0): no gap to bridge, so the region
        // is exactly the slop-grown frame — today's behavior for the default 12pt.
        let revealed = CGRect(x: 500, y: 0, width: 600, height: 70)
        let keep = DockLayout.keepRevealedFrame(revealed: revealed, screenFrame: screen,
                                                edge: .bottom, slop: 12)
        XCTAssertEqual(keep, revealed.insetBy(dx: -12, dy: -12))
    }

    func testInsetBottomDockExtendsToScreenEdge() {
        // Inset 40, slop 12: the 28pt strip between the slop region and the physical
        // edge must stay inside, or a pointer resting at the edge flaps reveal/hide.
        let revealed = CGRect(x: 500, y: 40, width: 600, height: 70)
        let keep = DockLayout.keepRevealedFrame(revealed: revealed, screenFrame: screen,
                                                edge: .bottom, slop: 12)
        XCTAssertEqual(keep.minY, screen.minY, accuracy: 0.001)
        XCTAssertEqual(keep.maxY, revealed.maxY + 12, accuracy: 0.001)
        XCTAssertEqual(keep.minX, revealed.minX - 12, accuracy: 0.001)
        XCTAssertEqual(keep.maxX, revealed.maxX + 12, accuracy: 0.001)
    }

    func testInsetTopAndRightDocksExtendTowardTheirEdges() {
        let top = DockLayout.keepRevealedFrame(
            revealed: CGRect(x: 500, y: 890, width: 600, height: 70),
            screenFrame: screen, edge: .top, slop: 20)
        XCTAssertEqual(top.maxY, screen.maxY, accuracy: 0.001)
        XCTAssertEqual(top.minY, 890 - 20, accuracy: 0.001)

        let right = DockLayout.keepRevealedFrame(
            revealed: CGRect(x: 1480, y: 200, width: 70, height: 600),
            screenFrame: screen, edge: .right, slop: 0)
        XCTAssertEqual(right.maxX, screen.maxX, accuracy: 0.001)
        XCTAssertEqual(right.minX, 1480, accuracy: 0.001)
    }

    func testZeroSlopInsetLeftDockStillBridgesTheGap() {
        // Hide distance 0 must still not flap on an inset dock: the gap band alone
        // keeps the dock up while the pointer sits at the physical edge.
        let revealed = CGRect(x: 50, y: 200, width: 70, height: 600)
        let keep = DockLayout.keepRevealedFrame(revealed: revealed, screenFrame: screen,
                                                edge: .left, slop: 0)
        XCTAssertEqual(keep.minX, screen.minX, accuracy: 0.001)
        XCTAssertTrue(keep.contains(CGPoint(x: 0.5, y: 500)))
        XCTAssertFalse(keep.contains(CGPoint(x: 121, y: 500)))
    }

    func testLargerSlopGrowsTheRegionEverywhere() {
        let revealed = CGRect(x: 500, y: 0, width: 600, height: 70)
        let small = DockLayout.keepRevealedFrame(revealed: revealed, screenFrame: screen,
                                                 edge: .bottom, slop: 12)
        let large = DockLayout.keepRevealedFrame(revealed: revealed, screenFrame: screen,
                                                 edge: .bottom, slop: 100)
        XCTAssertTrue(large.contains(small))
    }
}
