import AppKit
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

    // MARK: Drillability (FAB-B6)

    private func makeEntry(name: String, isDirectory: Bool, isPackage: Bool = false) -> FolderEntry {
        let url = URL(fileURLWithPath: "/tmp/\(name)", isDirectory: isDirectory)
        return FolderEntry(id: url.path, url: url, name: name, icon: NSImage(),
                           isDirectory: isDirectory, isPackage: isPackage)
    }

    func testDirectoryWithDottedNameIsDrillable() {
        // Ordinary folders with dots in the name (jquery-3.7.1, My.Project) must
        // drill in, not open in Finder (FAB-B6).
        XCTAssertTrue(FolderStack.isDrillable(makeEntry(name: "jquery-3.7.1", isDirectory: true)))
        XCTAssertTrue(FolderStack.isDrillable(makeEntry(name: "My.Project", isDirectory: true)))
    }

    func testPackageIsNotDrillable() {
        // Bundles (.app, .rtfd) are directories on disk but must open, not drill in.
        XCTAssertFalse(FolderStack.isDrillable(makeEntry(name: "Safari.app", isDirectory: true, isPackage: true)))
    }

    func testPlainFileIsNotDrillable() {
        XCTAssertFalse(FolderStack.isDrillable(makeEntry(name: "notes.txt", isDirectory: false)))
    }

    func testFolderEntryDefaultsIsPackageToFalse() {
        let url = URL(fileURLWithPath: "/tmp/plain", isDirectory: true)
        let entry = FolderEntry(id: url.path, url: url, name: "plain", icon: NSImage(), isDirectory: true)
        XCTAssertFalse(entry.isPackage)
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
        let dock = CGRect(x: 300, y: 0, width: 400, height: 70)
        // Near the right edge on a bottom dock: x must clamp so the panel stays on screen.
        let origin = FolderStack.origin(for: size, near: CGPoint(x: 990, y: 10), dock: dock, edge: .bottom, in: vf)
        XCTAssertLessThanOrEqual(origin.x + size.width, vf.maxX)
        XCTAssertGreaterThanOrEqual(origin.x, vf.minX)
        XCTAssertGreaterThanOrEqual(origin.y, vf.minY)
        XCTAssertLessThanOrEqual(origin.y + size.height, vf.maxY)
    }

    func testOriginBottomOpensClearOfDock() {
        let vf = CGRect(x: 0, y: 0, width: 2000, height: 1200)
        let size = CGSize(width: 200, height: 200)
        let dock = CGRect(x: 900, y: 0, width: 200, height: 70)
        let origin = FolderStack.origin(for: size, near: CGPoint(x: 1000, y: 30), dock: dock, edge: .bottom, in: vf)
        XCTAssertGreaterThanOrEqual(origin.y, dock.maxY)   // sits clear of the dock, not over it
    }
}
