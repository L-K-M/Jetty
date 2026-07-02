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

    func testDockAnchorClampsOffset() {
        // Init and the JSON decode path both clamp to the Settings slider range (H6).
        XCTAssertEqual(DockAnchor(offset: 99999).offset, 600)
        XCTAssertEqual(DockAnchor(offset: -99999).offset, -600)
        XCTAssertEqual(DockAnchor(offset: .nan).offset, 0)
        let decoded = try? JSONDecoder().decode(
            DockAnchor.self, from: Data(#"{ "offset": 5000 }"#.utf8))
        XCTAssertEqual(decoded?.offset, 600)
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

    func testPresetToleratesUnknownEnumRawValues() throws {
        // A future material / indicator style must fall back to defaults, not fail the
        // whole decode (F-M8) — decodeIfPresent throws on a present-but-unknown value.
        let json = Data("""
        { "material": "frostedGlass", "indicatorStyle": "sparkles", "tintHex": "#123456" }
        """.utf8)
        let preset = try XCTUnwrap(AppearancePreset.decode(from: json))
        XCTAssertEqual(preset.material, Preferences.Default.material)
        XCTAssertEqual(preset.indicatorStyle, Preferences.Default.indicatorStyle)
        XCTAssertEqual(preset.tintHex, "#123456")   // the valid fields still land
    }

    func testPresetRejectsNonThemeJSON() {
        // An object with none of the recognized theme keys (e.g. an exported dock.json)
        // is rejected rather than silently returning an all-defaults preset (M27).
        XCTAssertNil(AppearancePreset.decode(from: Data(#"{ "version": 1, "items": [] }"#.utf8)))
    }

    func testAccentGlowRoundTrips() throws {
        // The accent-glow toggle now survives export/import (F-M8).
        var preset = AppearancePreset.builtIns[0]
        preset.accentGlow = false
        let data = try JSONEncoder().encode(preset)
        XCTAssertEqual(try JSONDecoder().decode(AppearancePreset.self, from: data).accentGlow, false)
        // A theme predating the field decodes to the default (true), not false.
        let legacy = Data(#"{ "material": "liquidGlass", "tintHex": "#0A7AFF" }"#.utf8)
        XCTAssertEqual(try XCTUnwrap(AppearancePreset.decode(from: legacy)).accentGlow,
                       Preferences.Default.accentGlow)
    }

    func testNormalizeAngleWrapsAndGuards() {
        XCTAssertEqual(Preferences.normalizeAngle(370), 10, accuracy: 0.001)
        XCTAssertEqual(Preferences.normalizeAngle(-90), 270, accuracy: 0.001)
        XCTAssertEqual(Preferences.normalizeAngle(45), 45, accuracy: 0.001)
        // Non-finite inputs (the AngleDial crash trigger, F-H5) map to 0.
        XCTAssertEqual(Preferences.normalizeAngle(.infinity), 0)
        XCTAssertEqual(Preferences.normalizeAngle(.nan), 0)
        // A huge but finite value stays in range, so Int(_:) can't trap on it.
        let big = Preferences.normalizeAngle(1e300)
        XCTAssertTrue(big >= 0 && big < 360, "normalized angle must be in [0,360)")
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
