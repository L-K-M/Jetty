import XCTest
@testable import Jetty

final class CodableModelTests: XCTestCase {

    func testDockDocumentRoundTrip() throws {
        var doc = DockDocument()
        doc.items = [
            DockItem(kind: .application, displayName: "Finder", bundleIdentifier: "com.apple.finder"),
            DockItem(kind: .separator),
            DockItem(kind: .clock, displayName: "Clock"),
        ]
        doc.anchorsByDisplayUUID["UUID-1"] = DockAnchor(displayUUID: "UUID-1", edge: .right, alignment: .trailing, offset: 12, inset: 4)

        let data = try JSONEncoder().encode(doc)
        let decoded = try JSONDecoder().decode(DockDocument.self, from: data)
        XCTAssertEqual(decoded, doc)
    }

    func testDockDocumentDecodesEmptyObjectToDefaults() throws {
        let decoded = try JSONDecoder().decode(DockDocument.self, from: Data("{}".utf8))
        XCTAssertEqual(decoded.version, DockDocument.currentVersion)
        XCTAssertTrue(decoded.items.isEmpty)
        XCTAssertTrue(decoded.anchorsByDisplayUUID.isEmpty)
    }

    func testDockItemForwardCompatIgnoresUnknownAndFillsDefaults() throws {
        let json = Data("""
        { "kind": "application", "bundleIdentifier": "com.apple.Safari", "somethingNew": 42 }
        """.utf8)
        let item = try JSONDecoder().decode(DockItem.self, from: json)
        XCTAssertEqual(item.kind, .application)
        XCTAssertEqual(item.bundleIdentifier, "com.apple.Safari")
        XCTAssertTrue(item.displayName.isEmpty)
        XCTAssertNotNil(item.id)   // synthesized when absent
    }

    func testDockAnchorClampsInset() {
        XCTAssertEqual(DockAnchor(inset: -50).inset, 0)
        XCTAssertEqual(DockAnchor(inset: 99999).inset, 400)
    }

    func testDockAnchorDecodesMissingFieldsToDefaults() throws {
        let anchor = try JSONDecoder().decode(DockAnchor.self, from: Data("{}".utf8))
        XCTAssertEqual(anchor.edge, .bottom)
        XCTAssertEqual(anchor.alignment, .center)
        XCTAssertEqual(anchor.inset, 0)
    }

    func testAppearancePresetRoundTrip() throws {
        let preset = AppearancePreset.builtIns[0]
        let data = try JSONEncoder().encode(preset)
        let decoded = try JSONDecoder().decode(AppearancePreset.self, from: data)
        XCTAssertEqual(decoded, preset)
    }

    func testAppearancePresetBuiltInsNonEmpty() {
        XCTAssertFalse(AppearancePreset.builtIns.isEmpty)
        XCTAssertTrue(AppearancePreset.builtIns.contains { $0.name == "Tahoe Glass" })
    }
}
