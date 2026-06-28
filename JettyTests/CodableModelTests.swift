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

    func testDecodesLossilyDroppingUnknownKindButKeepingValidItems() throws {
        // A document from a hypothetical newer build with an unknown tile kind: the
        // unknown item is dropped; the valid ones survive (ISSUE-8).
        let json = Data("""
        { "version": 1, "items": [
            { "kind": "application", "bundleIdentifier": "com.apple.finder" },
            { "kind": "teleporter" },
            { "kind": "clock" }
        ] }
        """.utf8)
        let doc = try JSONDecoder().decode(DockDocument.self, from: json)
        XCTAssertEqual(doc.items.count, 2)
        XCTAssertEqual(doc.items.map(\.kind), [.application, .clock])
    }

    func testDecodesLossilyDroppingUnknownAnchorEdge() throws {
        let json = Data("""
        { "version": 1, "anchorsByDisplayUUID": {
            "GOOD": { "displayUUID": "GOOD", "edge": "left", "alignment": "center", "offset": 0, "inset": 0 },
            "BAD":  { "displayUUID": "BAD", "edge": "diagonal" }
        } }
        """.utf8)
        let doc = try JSONDecoder().decode(DockDocument.self, from: json)
        XCTAssertEqual(doc.anchorsByDisplayUUID.count, 1)
        XCTAssertEqual(doc.anchorsByDisplayUUID["GOOD"]?.edge, .left)
        XCTAssertNil(doc.anchorsByDisplayUUID["BAD"])
    }

    func testUnknownFolderDisplayKeepsItem() throws {
        // An unknown folderDisplay shouldn't drop the whole folder item (ISSUE-8).
        let json = Data("""
        { "kind": "folder", "displayName": "Docs", "folderDisplay": "spiral" }
        """.utf8)
        let item = try JSONDecoder().decode(DockItem.self, from: json)
        XCTAssertEqual(item.kind, .folder)
        XCTAssertEqual(item.displayName, "Docs")
        XCTAssertNil(item.folderDisplay)
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

    func testDecodePrefersJettyFormatRoundTrip() throws {
        let preset = AppearancePreset.builtIns.first { $0.name == "Vapor" }!
        let data = try JSONEncoder().encode(preset)
        XCTAssertEqual(AppearancePreset.decode(from: data), preset)
    }

    func testImportsZapTheme() throws {
        // A Zap-format theme (different field names) maps into a Jetty preset.
        let zapJSON = Data("""
        {
          "name": "ZX Night",
          "backgroundColorHex": "#0B0B1A",
          "useGradientBackground": true,
          "gradientColorHex": "#1A1140",
          "gradientAngle": 20,
          "decorationStyle": "zxSpectrum",
          "decorationPosition": "topTrailing",
          "crtEnabled": true,
          "crtIntensity": 0.5,
          "highlightColorHex": "#00AEEF",
          "backgroundOpacity": 0.7,
          "iconSize": 80,
          "cornerRadius": 14,
          "showAppName": true
        }
        """.utf8)
        let preset = try XCTUnwrap(AppearancePreset.decode(from: zapJSON))
        XCTAssertEqual(preset.material, .gradient)          // useGradientBackground → gradient
        XCTAssertEqual(preset.tintHex, "#0B0B1A")           // backgroundColorHex → tint
        XCTAssertEqual(preset.gradientHex, "#1A1140")
        XCTAssertEqual(preset.decorationStyle, "zxSpectrum")
        XCTAssertTrue(preset.crtEnabled)
        XCTAssertEqual(preset.indicatorHex, "#00AEEF")      // highlightColorHex → indicator
        XCTAssertEqual(preset.iconSize, 80, accuracy: 0.001)
    }
}
