import XCTest
@testable import Jetty

/// Pins `frameWidth`'s per-kind behaviour directly.
///
/// Deliberately *not* a test that `DockLayout.tileExtent` and `DockTileView.tileWidth`
/// agree: they now call this function, so such a test would compare it with itself and
/// could never fail — the vacuous shape that cost #79 four rounds. Every case below
/// distinguishes one branch of the switch from the others, and each was confirmed by
/// mutating that branch.
final class DockTileGeometryTests: XCTestCase {

    // A factor unlike the clock's resting one, so "used the argument" and "fell through
    // to kind.tileWidthFactor" cannot be confused for each other.
    private let zoomedClock: CGFloat = 3

    func testSeparatorIsAThinGapAlongHorizontalDocksOnly() {
        XCTAssertEqual(DockTileGeometry.frameWidth(kind: .separator, baseSize: 64, edge: .bottom,
                                                   clockWidthFactor: zoomedClock),
                       DockLayout.separatorExtent)
        // Vertical: the separator spans the dock's width, so it is a full base square.
        XCTAssertEqual(DockTileGeometry.frameWidth(kind: .separator, baseSize: 64, edge: .left,
                                                   clockWidthFactor: zoomedClock),
                       64)
    }

    func testClockUsesTheSuppliedFactorOnHorizontalDocksOnly() {
        XCTAssertEqual(DockTileGeometry.frameWidth(kind: .clock, baseSize: 64, edge: .bottom,
                                                   clockWidthFactor: zoomedClock),
                       64 * zoomedClock)
        // Vertical: a widening clock would overflow the strip, so the factor is ignored
        // and the tile takes its ordinary kind width.
        XCTAssertEqual(DockTileGeometry.frameWidth(kind: .clock, baseSize: 64, edge: .right,
                                                   clockWidthFactor: zoomedClock),
                       64 * DockItemKind.clock.tileWidthFactor)
    }

    func testEveryOtherKindIsItsOwnWidthFactorOnBothAxes() {
        for edge in [DockEdge.bottom, .top, .left, .right] {
            XCTAssertEqual(DockTileGeometry.frameWidth(kind: .application, baseSize: 64, edge: edge,
                                                       clockWidthFactor: zoomedClock),
                           64 * DockItemKind.application.tileWidthFactor, "edge \(edge)")
        }
    }

    func testEdgePaddingLandsOnTheEdgeFacingSideOnly() {
        XCTAssertEqual(DockTileGeometry.edgePadding(edge: .bottom, padding: 7),
                       DockTileGeometry.EdgePadding(bottom: 7))
        XCTAssertEqual(DockTileGeometry.edgePadding(edge: .top, padding: 7),
                       DockTileGeometry.EdgePadding(top: 7))
        XCTAssertEqual(DockTileGeometry.edgePadding(edge: .left, padding: 7),
                       DockTileGeometry.EdgePadding(leading: 7))
        XCTAssertEqual(DockTileGeometry.edgePadding(edge: .right, padding: 7),
                       DockTileGeometry.EdgePadding(trailing: 7))
    }

    /// The axis swap is `tileExtent`'s own contribution on top of `frameWidth`, and is
    /// the part a shared implementation does *not* make automatic.
    func testTileExtentSwapsTheAxesByEdge() {
        let horizontal = DockLayout.tileExtent(kind: .separator, baseSize: 64, edge: .bottom)
        XCTAssertEqual(horizontal.along, DockLayout.separatorExtent)
        XCTAssertEqual(horizontal.across, 64)

        let vertical = DockLayout.tileExtent(kind: .separator, baseSize: 64, edge: .left)
        XCTAssertEqual(vertical.along, 64, "along a vertical dock, height is the along axis")
        XCTAssertEqual(vertical.across, 64)
    }
}
