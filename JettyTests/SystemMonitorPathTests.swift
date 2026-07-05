import XCTest
import SwiftUI
@testable import Jetty

/// Coverage for the System Monitor's pure path geometry (FAB-T2 #1) and the
/// per-style network gate (FAB-T2 #6). `linePath`/`areaPath` draw every frame
/// of the graph and scope styles, so their clamping/inversion/degenerate-input
/// behavior is pinned down here.
final class SystemMonitorPathTests: XCTestCase {

    // MARK: linePath

    func testLinePathClampsOutOfRangeValuesAndInvertsY() {
        let size = CGSize(width: 100, height: 100)
        let path = SystemMonitorGraph.linePath([0, 2, -1], in: size)
        var expected = Path()
        expected.move(to: CGPoint(x: 0, y: 100))       // 0 → baseline (y inverted)
        expected.addLine(to: CGPoint(x: 50, y: 0))     // 2 clamps to 1 → top edge
        expected.addLine(to: CGPoint(x: 100, y: 100))  // -1 clamps to 0 → baseline
        XCTAssertEqual(path.description, expected.description)
    }

    func testLinePathValueOneMapsToTopEdge() {
        // y is inverted: a full-scale value draws at y == 0, not y == height.
        let path = SystemMonitorGraph.linePath([1, 1], in: CGSize(width: 80, height: 40))
        XCTAssertEqual(path.boundingRect, CGRect(x: 0, y: 0, width: 80, height: 0))
    }

    func testLinePathSpansFullWidthWithEvenSteps() {
        // Five samples across 120pt → step 30pt; a flat 0.5 line sits at mid-height.
        let path = SystemMonitorGraph.linePath([0.5, 0.5, 0.5, 0.5, 0.5],
                                               in: CGSize(width: 120, height: 60))
        XCTAssertEqual(path.boundingRect, CGRect(x: 0, y: 30, width: 120, height: 0))
    }

    func testLinePathDegenerateInputsAreEmpty() {
        let size = CGSize(width: 100, height: 100)
        XCTAssertTrue(SystemMonitorGraph.linePath([], in: size).isEmpty)
        XCTAssertTrue(SystemMonitorGraph.linePath([0.5], in: size).isEmpty)
        XCTAssertTrue(SystemMonitorGraph.linePath([0.2, 0.8], in: CGSize(width: 0, height: 100)).isEmpty)
        XCTAssertTrue(SystemMonitorGraph.linePath([0.2, 0.8], in: CGSize(width: 100, height: 0)).isEmpty)
    }

    // MARK: areaPath

    func testAreaPathClosesDownToTheBaseline() {
        let size = CGSize(width: 100, height: 50)
        let area = SystemMonitorGraph.areaPath([0.5, 1], in: size)
        // The area is the line path plus two baseline legs and a close.
        var expected = SystemMonitorGraph.linePath([0.5, 1], in: size)
        expected.addLine(to: CGPoint(x: 100, y: 50))   // down from the last sample
        expected.addLine(to: CGPoint(x: 0, y: 50))     // along the baseline
        expected.closeSubpath()
        XCTAssertEqual(area.description, expected.description)
        // The closed region reaches the baseline and encloses points under the line.
        XCTAssertEqual(area.boundingRect, CGRect(x: 0, y: 0, width: 100, height: 50))
        XCTAssertTrue(area.contains(CGPoint(x: 50, y: 40)))
    }

    func testAreaPathDegenerateInputsAreEmpty() {
        XCTAssertTrue(SystemMonitorGraph.areaPath([], in: CGSize(width: 100, height: 100)).isEmpty)
        XCTAssertTrue(SystemMonitorGraph.areaPath([0.5], in: CGSize(width: 100, height: 100)).isEmpty)
        XCTAssertTrue(SystemMonitorGraph.areaPath([0.2, 0.8], in: .zero).isEmpty)
    }

    // MARK: SystemMonitorStyle.supportsNetwork

    func testOnlyTimeSeriesStylesSupportNetwork() {
        XCTAssertTrue(SystemMonitorStyle.graph.supportsNetwork)
        XCTAssertTrue(SystemMonitorStyle.scope.supportsNetwork)
        XCTAssertFalse(SystemMonitorStyle.bars.supportsNetwork)
        XCTAssertFalse(SystemMonitorStyle.led.supportsNetwork)
        XCTAssertFalse(SystemMonitorStyle.gauges.supportsNetwork)
    }
}
