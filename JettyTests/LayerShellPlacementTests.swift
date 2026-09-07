import XCTest
#if canImport(CoreGraphics)
import CoreGraphics
#endif
@testable import Jetty

/// `DockLayout.layerShellPlacement` — the geometry contract JP-24's Wayland binding
/// consumes. Every case runs against the same 1000×800 output the rest of
/// `DockLayoutTests` uses, so the frames here are the frames the dock really gets.
final class LayerShellPlacementTests: XCTestCase {

    private let bounds = CGRect(x: 0, y: 0, width: 1000, height: 800)

    private func placement(_ anchor: DockAnchor, size: CGSize) -> LayerShellPlacement {
        let frame = DockLayout.revealedFrame(anchor: anchor, contentSize: size, in: bounds)
        return DockLayout.layerShellPlacement(frame: frame, in: bounds, edge: anchor.edge)
    }

    // MARK: Every edge

    func testBottomDockAnchorsBottomLeftWithBothMargins() {
        // 300×70 centred on a 1000-wide output, lifted 12pt off the edge.
        let p = placement(DockAnchor(edge: .bottom, alignment: .center, inset: 12),
                          size: CGSize(width: 300, height: 70))
        XCTAssertEqual(p.anchorEdges, [.bottom, .left])
        XCTAssertEqual(p.margins.bottom, 12)
        XCTAssertEqual(p.margins.left, 350)          // (1000 - 300) / 2
        XCTAssertEqual(p.margins.top, 0)
        XCTAssertEqual(p.margins.right, 0)
    }

    func testTopDockAnchorsTopLeftAndMeasuresFromTheTop() {
        let p = placement(DockAnchor(edge: .top, alignment: .center, inset: 12),
                          size: CGSize(width: 300, height: 70))
        XCTAssertEqual(p.anchorEdges, [.top, .left])
        XCTAssertEqual(p.margins.top, 12)
        XCTAssertEqual(p.margins.left, 350)
        XCTAssertEqual(p.margins.bottom, 0)
        XCTAssertEqual(p.margins.right, 0)
    }

    func testLeftDockAnchorsLeftTop() {
        // A vertical dock: 70 wide × 300 tall, centred along the 800-tall edge.
        let p = placement(DockAnchor(edge: .left, alignment: .center, inset: 12),
                          size: CGSize(width: 70, height: 300))
        XCTAssertEqual(p.anchorEdges, [.left, .top])
        XCTAssertEqual(p.margins.left, 12)
        XCTAssertEqual(p.margins.top, 250)           // (800 - 300) / 2
        XCTAssertEqual(p.margins.bottom, 0)
        XCTAssertEqual(p.margins.right, 0)
    }

    func testRightDockAnchorsRightTopAndMeasuresFromTheRight() {
        let p = placement(DockAnchor(edge: .right, alignment: .center, inset: 12),
                          size: CGSize(width: 70, height: 300))
        XCTAssertEqual(p.anchorEdges, [.right, .top])
        XCTAssertEqual(p.margins.right, 12)
        XCTAssertEqual(p.margins.top, 250)
        XCTAssertEqual(p.margins.bottom, 0)
        XCTAssertEqual(p.margins.left, 0)
    }

    // MARK: The margin always belongs to an anchored edge

    /// The bug this whole type exists to prevent: a margin set on an edge the surface
    /// is not anchored to is discarded by the compositor with no error, and the dock
    /// silently lands in the wrong place. Assert it for every edge at once.
    func testEveryNonZeroMarginSitsOnAnAnchoredEdge() {
        for edge in DockEdge.allCases {
            let size = edge.isHorizontal ? CGSize(width: 300, height: 70)
                                         : CGSize(width: 70, height: 300)
            // Off-centre and inset, so both margins are non-zero and nothing passes by
            // being accidentally zero everywhere.
            let p = placement(DockAnchor(edge: edge, alignment: .leading, offset: 40, inset: 12),
                              size: size)
            XCTAssertEqual(p.anchorEdges.count, 2, "\(edge): expected a corner anchor")
            let m = p.margins
            let byEdge: [DockEdge: Int32] = [.top: m.top, .right: m.right,
                                             .bottom: m.bottom, .left: m.left]
            for (side, value) in byEdge where !p.anchorEdges.contains(side) {
                XCTAssertEqual(value, 0, "\(edge) dock: margin on unanchored edge \(side)")
            }
            XCTAssertTrue(p.anchorEdges.contains(edge), "\(edge): dock edge must be anchored")
        }
    }

    /// The two anchored edges must be orthogonal — the protocol resolves an orthogonal
    /// pair to a corner, which is what centre-plus-offset placement needs; a parallel
    /// pair (left+right) would stretch the surface instead.
    func testAnchorsAreAlwaysOrthogonal() {
        for edge in DockEdge.allCases {
            let p = placement(DockAnchor(edge: edge), size: CGSize(width: 300, height: 70))
            // `isVertical` describes the *edge*: left/right are the vertical sides.
            let leftOrRight = p.anchorEdges.filter { $0.isVertical }
            let topOrBottom = p.anchorEdges.filter { $0.isHorizontal }
            XCTAssertEqual(leftOrRight.count, 1, "\(edge): expected exactly one of left/right")
            XCTAssertEqual(topOrBottom.count, 1, "\(edge): expected exactly one of top/bottom")
        }
    }

    // MARK: Alignment and offset survive the conversion

    func testLeadingAndTrailingBottomDocksDifferOnlyInTheLeftMargin() {
        let size = CGSize(width: 300, height: 70)
        let leading = placement(DockAnchor(edge: .bottom, alignment: .leading), size: size)
        let trailing = placement(DockAnchor(edge: .bottom, alignment: .trailing), size: size)
        XCTAssertEqual(leading.margins.left, 0)
        XCTAssertEqual(trailing.margins.left, 700)     // 1000 - 300
        XCTAssertEqual(leading.anchorEdges, trailing.anchorEdges)
    }

    /// A vertical dock's `leading` is the *top* of the screen (`alignAlong`'s reversed
    /// axis), so leading must produce the smaller top margin, not the larger one.
    func testVerticalLeadingIsTheTopOfTheScreen() {
        let size = CGSize(width: 70, height: 300)
        let leading = placement(DockAnchor(edge: .left, alignment: .leading), size: size)
        let trailing = placement(DockAnchor(edge: .left, alignment: .trailing), size: size)
        XCTAssertEqual(leading.margins.top, 0)
        XCTAssertEqual(trailing.margins.top, 500)      // 800 - 300
    }

    func testOffsetMovesTheAlongMargin() {
        let size = CGSize(width: 300, height: 70)
        let centred = placement(DockAnchor(edge: .bottom, alignment: .center), size: size)
        let nudged = placement(DockAnchor(edge: .bottom, alignment: .center, offset: 40), size: size)
        XCTAssertEqual(nudged.margins.left - centred.margins.left, 40)
    }

    // MARK: Hidden frames, rounding, and the exclusive zone

    /// `hiddenFrame` slides the dock off its edge; the margin has to go negative to
    /// say so. Clamping at zero would leave the hidden dock pinned on screen.
    func testHiddenBottomDockProducesANegativeBottomMargin() {
        let anchor = DockAnchor(edge: .bottom, alignment: .center)
        let size = CGSize(width: 300, height: 70)
        let revealed = DockLayout.revealedFrame(anchor: anchor, contentSize: size, in: bounds)
        let hidden = DockLayout.hiddenFrame(edge: .bottom, revealedFrame: revealed, in: bounds)
        let p = DockLayout.layerShellPlacement(frame: hidden, in: bounds, edge: .bottom)
        XCTAssertEqual(p.margins.bottom, -70)          // fully off-edge: -(height - edgeReveal)
        XCTAssertEqual(p.margins.left, 350)            // along-edge position is unchanged
    }

    func testFractionalGapsRoundToTheNearestPoint() {
        // 301 wide on a 1000-wide output leaves 349.5 either side.
        let p = placement(DockAnchor(edge: .bottom, alignment: .center),
                          size: CGSize(width: 301, height: 70))
        XCTAssertEqual(p.margins.left, 350)            // 349.5 rounds away from zero
    }

    func testNonFiniteFrameDoesNotTrap() {
        // `.nan` alone is ambiguous on Linux (Foundation.CGFloat and Swift.Double both
        // offer it); spelling the type keeps this compiling on both platforms.
        let frame = CGRect(x: CGFloat.nan, y: 0, width: 300, height: 70)
        let p = DockLayout.layerShellPlacement(frame: frame, in: bounds, edge: .bottom)
        XCTAssertEqual(p.margins.left, 0)
        XCTAssertEqual(p.margins.bottom, 0)
    }

    func testHugeFrameSaturatesInsteadOfTrapping() {
        let frame = CGRect(x: 1e30, y: 0, width: 300, height: 70)
        let p = DockLayout.layerShellPlacement(frame: frame, in: bounds, edge: .bottom)
        XCTAssertEqual(p.margins.left, Int32.max)
    }

    /// Jetty reserves no screen space on any platform — the one load-bearing design
    /// decision. If this ever needs changing, it is a product decision, not a fix.
    func testExclusiveZoneIsAlwaysZero() {
        for edge in DockEdge.allCases {
            let p = placement(DockAnchor(edge: edge), size: CGSize(width: 300, height: 70))
            XCTAssertEqual(p.exclusiveZone, 0, "\(edge)")
        }
    }
}
