import XCTest
@testable import Jetty

final class MenuGlyphAndStoreTests: XCTestCase {

    // MARK: JettyMenuGlyph (Task 3)

    func testGlyphValidationAndResolution() {
        XCTAssertTrue(JettyMenuGlyph.isValid("square.grid.2x2.fill"))
        XCTAssertFalse(JettyMenuGlyph.isValid("definitely.not.a.symbol.xyz"))
        XCTAssertFalse(JettyMenuGlyph.isValid("  "))
        // A valid name resolves to itself; an unknown one falls back (lenient).
        XCTAssertEqual(JettyMenuGlyph.resolved("star.fill"), "star.fill")
        XCTAssertEqual(JettyMenuGlyph.resolved("nope.nope.nope"), JettyMenuGlyph.fallback)
        // Whitespace is trimmed.
        XCTAssertEqual(JettyMenuGlyph.resolved("  star.fill  "), "star.fill")
    }

    func testGlyphAvailableOptionsNonEmptyAndValid() {
        XCTAssertFalse(JettyMenuGlyph.availableOptions.isEmpty)
        XCTAssertTrue(JettyMenuGlyph.availableOptions.allSatisfy(JettyMenuGlyph.isValid))
        XCTAssertTrue(JettyMenuGlyph.availableOptions.contains(JettyMenuGlyph.fallback))
    }

    // MARK: DockStore backup guard (ISSUE-9)

    func testFileDecodesDistinguishesGoodFromCorrupt() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("JettyStoreTest-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let good = dir.appendingPathComponent("good.json")
        try JSONEncoder().encode(DockDocument()).write(to: good)
        XCTAssertTrue(DockStore.fileDecodes(good))

        let corrupt = dir.appendingPathComponent("corrupt.json")
        try Data("{ this is not json".utf8).write(to: corrupt)
        XCTAssertFalse(DockStore.fileDecodes(corrupt))

        let missing = dir.appendingPathComponent("nope.json")
        XCTAssertFalse(DockStore.fileDecodes(missing))
    }
}
