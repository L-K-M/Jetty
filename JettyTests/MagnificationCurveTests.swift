import XCTest
import CoreGraphics
@testable import Jetty

final class MagnificationCurveTests: XCTestCase {

    func testPeakAtZeroDistance() {
        XCTAssertEqual(MagnificationCurve.scale(distance: 0, influence: 100, maxScale: 1.5), 1.5, accuracy: 0.0001)
    }

    func testFallsToOneAtAndBeyondInfluence() {
        XCTAssertEqual(MagnificationCurve.scale(distance: 100, influence: 100, maxScale: 1.5), 1, accuracy: 0.0001)
        XCTAssertEqual(MagnificationCurve.scale(distance: 250, influence: 100, maxScale: 1.5), 1, accuracy: 0.0001)
    }

    func testMonotonicDecreasing() {
        let a = MagnificationCurve.scale(distance: 20, influence: 100, maxScale: 1.8)
        let b = MagnificationCurve.scale(distance: 50, influence: 100, maxScale: 1.8)
        let c = MagnificationCurve.scale(distance: 80, influence: 100, maxScale: 1.8)
        XCTAssertGreaterThan(a, b)
        XCTAssertGreaterThan(b, c)
        XCTAssertGreaterThan(a, 1)
    }

    func testDisabledWhenMaxScaleIsOne() {
        XCTAssertEqual(MagnificationCurve.scale(distance: 0, influence: 100, maxScale: 1.0), 1, accuracy: 0.0001)
    }

    func testSymmetricAroundZero() {
        let left = MagnificationCurve.scale(distance: -40, influence: 100, maxScale: 1.5)
        let right = MagnificationCurve.scale(distance: 40, influence: 100, maxScale: 1.5)
        XCTAssertEqual(left, right, accuracy: 0.0001)
    }
}
