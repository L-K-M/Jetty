import XCTest
@testable import Jetty

final class DockContextMenuPlacementTests: XCTestCase {

    private let visible = CGRect(x: 0, y: 0, width: 1600, height: 1000)
    private let menu = CGSize(width: 240, height: 300)

    func testBottomMenuOpensAboveDock() {
        let dock = CGRect(x: 500, y: 0, width: 600, height: 70)
        let point = DockContextMenuPlacement.topLeft(
            menuSize: menu, sourcePoint: CGPoint(x: 800, y: 20), dockFrame: dock,
            visibleFrame: visible, edge: .bottom)
        XCTAssertEqual(point.y - menu.height, dock.maxY + 6, accuracy: 0.001)
    }

    func testTopMenuOpensBelowDock() {
        let dock = CGRect(x: 500, y: 930, width: 600, height: 70)
        let point = DockContextMenuPlacement.topLeft(
            menuSize: menu, sourcePoint: CGPoint(x: 800, y: 980), dockFrame: dock,
            visibleFrame: visible, edge: .top)
        XCTAssertEqual(point.y, dock.minY - 6, accuracy: 0.001)
    }

    func testLeftMenuOpensRightOfDock() {
        let dock = CGRect(x: 0, y: 200, width: 70, height: 600)
        let point = DockContextMenuPlacement.topLeft(
            menuSize: menu, sourcePoint: CGPoint(x: 20, y: 500), dockFrame: dock,
            visibleFrame: visible, edge: .left)
        XCTAssertEqual(point.x, dock.maxX + 6, accuracy: 0.001)
    }

    func testRightMenuOpensLeftOfDock() {
        let dock = CGRect(x: 1530, y: 200, width: 70, height: 600)
        let point = DockContextMenuPlacement.topLeft(
            menuSize: menu, sourcePoint: CGPoint(x: 1580, y: 500), dockFrame: dock,
            visibleFrame: visible, edge: .right)
        XCTAssertEqual(point.x + menu.width, dock.minX - 6, accuracy: 0.001)
    }

    func testMenuClampsOnNegativeOriginDisplay() {
        let frame = CGRect(x: -1600, y: -200, width: 1600, height: 1000)
        let dock = CGRect(x: -200, y: -200, width: 200, height: 70)
        let point = DockContextMenuPlacement.topLeft(
            menuSize: menu, sourcePoint: CGPoint(x: -5, y: -180), dockFrame: dock,
            visibleFrame: frame, edge: .bottom)
        XCTAssertGreaterThanOrEqual(point.x, frame.minX + 4)
        XCTAssertLessThanOrEqual(point.x + menu.width, frame.maxX - 4)
        XCTAssertGreaterThanOrEqual(point.y - menu.height, frame.minY + 4)
        XCTAssertLessThanOrEqual(point.y, frame.maxY - 4)
    }

    func testDockStripFrameUsesConfiguredEdge() {
        let panel = CGRect(x: 100, y: 200, width: 600, height: 180)
        XCTAssertEqual(DockContextMenuPlacement.dockStripFrame(
            panelFrame: panel, thickness: 70, edge: .bottom),
                       CGRect(x: 100, y: 200, width: 600, height: 70))
        XCTAssertEqual(DockContextMenuPlacement.dockStripFrame(
            panelFrame: panel, thickness: 70, edge: .top),
                       CGRect(x: 100, y: 310, width: 600, height: 70))
        XCTAssertEqual(DockContextMenuPlacement.dockStripFrame(
            panelFrame: panel, thickness: 70, edge: .left),
                       CGRect(x: 100, y: 200, width: 70, height: 180))
        XCTAssertEqual(DockContextMenuPlacement.dockStripFrame(
            panelFrame: panel, thickness: 70, edge: .right),
                       CGRect(x: 630, y: 200, width: 70, height: 180))
    }
}
