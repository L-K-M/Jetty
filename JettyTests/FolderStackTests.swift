import XCTest
@testable import Jetty

final class FolderStackTests: XCTestCase {

    func testOrderingPutsDirectoriesFirstThenCaseInsensitiveName() {
        let input: [(name: String, isDirectory: Bool)] = [
            ("zebra", false), ("Apple", true), ("banana", false), ("apps", true), ("Beta", false),
        ]
        let sorted = input.sorted { FolderStack.orderedBefore($0, $1) }
        XCTAssertEqual(sorted.map(\.name), ["Apple", "apps", "banana", "Beta", "zebra"])
    }

    func testPanelSizeGridGrowsWithCountButCaps() {
        let small = FolderStack.panelSize(style: .grid, count: 4)
        let big = FolderStack.panelSize(style: .grid, count: 200)
        XCTAssertGreaterThan(small.width, 0)
        XCTAssertLessThanOrEqual(big.height, FolderStack.maxPanelHeight)
    }

    func testPanelSizeHandlesEmpty() {
        let size = FolderStack.panelSize(style: .list, count: 0)
        XCTAssertGreaterThan(size.height, 0)
        XCTAssertGreaterThan(size.width, 0)
    }

    func testOriginClampsWithinVisibleFrame() {
        let vf = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let size = CGSize(width: 300, height: 400)
        // Near the right edge on a bottom dock: x must clamp so the panel stays on screen.
        let origin = FolderStack.origin(for: size, near: CGPoint(x: 990, y: 10), edge: .bottom, in: vf)
        XCTAssertLessThanOrEqual(origin.x + size.width, vf.maxX)
        XCTAssertGreaterThanOrEqual(origin.x, vf.minX)
        XCTAssertGreaterThanOrEqual(origin.y, vf.minY)
        XCTAssertLessThanOrEqual(origin.y + size.height, vf.maxY)
    }

    func testOriginBottomOpensAbovePoint() {
        let vf = CGRect(x: 0, y: 0, width: 2000, height: 1200)
        let size = CGSize(width: 200, height: 200)
        let origin = FolderStack.origin(for: size, near: CGPoint(x: 1000, y: 30), edge: .bottom, in: vf)
        XCTAssertGreaterThan(origin.y, 30)   // sits above the click on a bottom dock
    }
}
