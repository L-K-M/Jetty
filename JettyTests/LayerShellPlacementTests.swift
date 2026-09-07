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

    /// The only test that exercises `Equatable`, which the type declares and JP-24
    /// will lean on: a Wayland binding that re-commits `set_anchor`/`set_margin` on
    /// every frame wants to skip the ones that changed nothing, and that diff is this
    /// `==`. All three cases are needed, and each covers a different broken `==`
    /// (measured, not assumed). Equality alone has almost no teeth: both sides carry
    /// identical margins *and* identical anchors, so an `==` comparing either field
    /// alone passes it. Differing by one margin fails an `==` that ignores margins;
    /// differing by one anchor fails an `==` that ignores anchors. Drop either
    /// inequality case and half the contract goes unchecked.
    func testWholePlacementEquality() {
        let p = placement(DockAnchor(edge: .bottom, alignment: .center, inset: 12),
                          size: CGSize(width: 300, height: 70))
        let expected = LayerShellPlacement(
            anchorEdges: [.bottom, .left],
            margins: LayerShellPlacement.Margins(top: 0, right: 0, bottom: 12, left: 350))
        XCTAssertEqual(p, expected)

        let oneMarginOff = LayerShellPlacement(
            anchorEdges: [.bottom, .left],
            margins: LayerShellPlacement.Margins(top: 0, right: 0, bottom: 12, left: 351))
        XCTAssertNotEqual(p, oneMarginOff)

        let oneAnchorOff = LayerShellPlacement(
            anchorEdges: [.bottom, .right],
            margins: LayerShellPlacement.Margins(top: 0, right: 0, bottom: 12, left: 350))
        XCTAssertNotEqual(p, oneAnchorOff)
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
            // Without this half the test passes on an implementation that drops
            // `offset` and `inset` entirely and returns four zeros — every assertion
            // above would still hold.
            for (side, value) in byEdge where p.anchorEdges.contains(side) {
                XCTAssertGreaterThan(value, 0,
                                     "\(edge) dock: anchored edge \(side) carries no margin")
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
        // Both inset, for two reasons: the cross-edge margin the name calls unchanged
        // then carries a value, where `0 == 0` would have asserted nothing; and this
        // is the suite's only `.trailing` × non-zero-inset case (the all-edges test
        // uses `.leading`, the per-edge ones `.center`).
        let leading = placement(DockAnchor(edge: .bottom, alignment: .leading, inset: 12),
                                size: size)
        let trailing = placement(DockAnchor(edge: .bottom, alignment: .trailing, inset: 12),
                                 size: size)
        XCTAssertEqual(leading.margins.left, 0)
        XCTAssertEqual(trailing.margins.left, 700)     // 1000 - 300

        // The "only" in the name, asserted rather than implied: the inset belongs to
        // the dock's own edge and must not move with the alignment.
        XCTAssertEqual(leading.margins.bottom, 12)
        XCTAssertEqual(trailing.margins.bottom, leading.margins.bottom)
        XCTAssertEqual(trailing.margins.top, leading.margins.top)
        XCTAssertEqual(trailing.margins.right, leading.margins.right)
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
        XCTAssertEqual(p.margins.left, 350)

        // 349.5 lands on 350 under away-from-zero *and* under nearest-even, since 350
        // is the even neighbour — so the case above cannot see which mode is in use.
        // 350.5 can: away-from-zero gives 351, nearest-even gives 350. This is the
        // assertion that actually pins `rounded()`'s default.
        let tie = placement(DockAnchor(edge: .bottom, alignment: .center),
                            size: CGSize(width: 299, height: 70))
        XCTAssertEqual(tie.margins.left, 351)
    }

    /// Both axes and both kinds of non-finite go through the same sanitiser, so all
    /// four combinations are driven here. A guard written as `isNaN` alone passes
    /// `Int32(Double.infinity)` to the conversion and traps; one written as `isFinite`
    /// alone has nowhere to send NaN, whose every comparison is false.
    ///
    /// The expectations encode "fail hidden": a corrupt coordinate drives its own
    /// margin off-output, never to 0, which on an anchored edge is flush with the
    /// screen edge and fully visible. Infinity keeps its sign rather than collapsing
    /// into the NaN case.
    ///
    /// `.nan` alone is ambiguous on Linux (`Foundation.CGFloat` and `Swift.Double`
    /// both offer it); spelling the type keeps this compiling on both platforms.
    func testNonFiniteFrameDoesNotTrap() {
        // frame, expected left (anchored), expected bottom (anchored)
        let cases: [(CGRect, Int32, Int32)] = [
            (CGRect(x: CGFloat.nan, y: 0, width: 300, height: 70), .min, 0),
            (CGRect(x: 0, y: CGFloat.nan, width: 300, height: 70), 0, .min),
            (CGRect(x: CGFloat.infinity, y: 0, width: 300, height: 70), .max, 0),
            (CGRect(x: 0, y: -CGFloat.infinity, width: 300, height: 70), 0, .min),
        ]
        for (frame, left, bottom) in cases {
            let p = DockLayout.layerShellPlacement(frame: frame, in: bounds, edge: .bottom)
            XCTAssertEqual(p.margins.left, left, "left for \(frame)")
            XCTAssertEqual(p.margins.bottom, bottom, "bottom for \(frame)")
            XCTAssertEqual(p.margins.top, 0, "unanchored edges stay zero even here")
            XCTAssertEqual(p.margins.right, 0, "unanchored edges stay zero even here")
        }
    }

    /// The rounding direction on the negative side — the side that actually shows.
    /// `edgeReveal` is 0 so a hidden dock peeks by nothing; rounding a fractional
    /// height toward zero instead of away from it would leave half a point of it on
    /// screen, on every output whose layout lands on a fraction.
    func testFractionalHiddenFrameRoundsFullyOffEdge() {
        let revealed = CGRect(x: 350, y: 0, width: 300, height: 60.5)
        let hidden = DockLayout.hiddenFrame(edge: .bottom, revealedFrame: revealed, in: bounds)
        let p = DockLayout.layerShellPlacement(frame: hidden, in: bounds, edge: .bottom)
        XCTAssertEqual(p.margins.bottom, -61)   // -60 would leave 0.5pt showing
    }

    func testHugeFrameSaturatesInsteadOfTrapping() {
        let frame = CGRect(x: 1e30, y: 0, width: 300, height: 70)
        let p = DockLayout.layerShellPlacement(frame: frame, in: bounds, edge: .bottom)
        XCTAssertEqual(p.margins.left, Int32.max)

        // Both ends, and the low one is the reachable half: hidden docks go negative
        // by design, so a clamp written only against `Int32.max` would trap exactly
        // where the type deliberately allows negative margins.
        let farBelow = CGRect(x: 0, y: -1e30, width: 300, height: 70)
        let q = DockLayout.layerShellPlacement(frame: farBelow, in: bounds, edge: .bottom)
        XCTAssertEqual(q.margins.bottom, Int32.min)
    }

    /// The input convention, pinned: `layerShellPlacement` reads `minY` as the
    /// output's **bottom** edge, the y-up convention `DockLayout` uses throughout. The
    /// same rectangle read y-down would put this dock at the top of the output and
    /// swap the two margins, so this is the assertion that fails if a future caller
    /// hands the function a y-down rect — or if someone "fixes" the arithmetic to
    /// accept one.
    func testFramesAreReadYUp() {
        // Flush against y = 0 and 70 tall. Y-up, that is a dock on the bottom edge;
        // y-down it would be a dock on the top edge.
        let frame = CGRect(x: 0, y: 0, width: 300, height: 70)
        let p = DockLayout.layerShellPlacement(frame: frame, in: bounds, edge: .bottom)
        XCTAssertEqual(p.margins.bottom, 0, "y-up: minY = 0 means flush with the bottom")
        XCTAssertEqual(p.margins.top, 0, "top is unanchored for a bottom dock")

        // The same frame read as a top dock: its gap to the top is the full remainder,
        // which is only true if maxY is being read as the frame's top edge.
        let asTop = DockLayout.layerShellPlacement(frame: frame, in: bounds, edge: .top)
        XCTAssertEqual(asTop.margins.top, 730)      // 800 - 70
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
