import XCTest
#if canImport(AppKit)
import AppKit
import SwiftUI
#endif
@testable import Jetty

/// The hex format's rules belong to `RGBA8` and are asserted against it directly, so
/// they run wherever a `dock.json` is read — the format is a storage contract between
/// builds, not a macOS detail. The `NSColor`/`Color` bridge keeps its own guarded
/// section, because converting to a live colour is the part that genuinely needs a
/// colour framework. Split in `docs/linux-port-plan.md` §JP-04.
final class ColorHexTests: XCTestCase {

    // MARK: The format

    func testParsesSixDigitHex() {
        XCTAssertEqual(RGBA8(hex: "#FF0000"), RGBA8(red: 255, green: 0, blue: 0))
    }

    func testLeadingHashOptional() {
        XCTAssertNotNil(RGBA8(hex: "00FF00"))
        XCTAssertEqual(RGBA8(hex: "00FF00"), RGBA8(hex: "#00FF00"))
    }

    func testInvalidReturnsNil() {
        XCTAssertNil(RGBA8(hex: "nothex"))
        XCTAssertNil(RGBA8(hex: "#FFFFF"))  // 5 digits is not a valid form
        XCTAssertNil(RGBA8(hex: ""))
        XCTAssertNil(RGBA8(hex: "#"))
    }

    func testSignedHexRejected() {
        // `UInt64(_, radix: 16)` accepts a leading "+"; the parser must not (FAB-B15).
        XCTAssertNil(RGBA8(hex: "+ABCDE"))
        XCTAssertNil(RGBA8(hex: "+ABCDEF"))
        XCTAssertNil(RGBA8(hex: "#+ABCDE"))
        XCTAssertNil(RGBA8(hex: "-ABCDEF"))
    }

    func testShorthandRGBExpandsNibbles() {
        // #abc must decode exactly like #aabbcc (L10).
        XCTAssertEqual(RGBA8(hex: "#abc")?.hexString, "#AABBCC")
        XCTAssertEqual(RGBA8(hex: "#abc"), RGBA8(hex: "#aabbcc"))
    }

    func testShorthandRGBAParsesWithAlpha() {
        XCTAssertEqual(RGBA8(hex: "#abcd"),
                       RGBA8(red: 0xAA, green: 0xBB, blue: 0xCC, alpha: 0xDD))
    }

    func testHexStringRoundTrip() {
        XCTAssertEqual(RGBA8(hex: "#3A7BD5")?.hexString, "#3A7BD5")
    }

    func testOpaqueColorEmitsSixDigits() {
        // Fully opaque stays #RRGGBB — even when parsed from an 8-digit string.
        XCTAssertEqual(RGBA8(hex: "#3A7BD5FF")?.hexString, "#3A7BD5")
    }

    func testAlphaRoundTripsThroughHexString() {
        // Translucent colors emit #RRGGBBAA and survive a parse → format cycle (L9).
        XCTAssertEqual(RGBA8(hex: "#3A7BD580")?.hexString, "#3A7BD580")
        XCTAssertEqual(RGBA8(hex: "#3A7BD500")?.hexString, "#3A7BD500")
    }

    /// Components outside 0...1 clamp instead of formatting to a string that no longer
    /// parses — the bug that turned a wide-gamut colour into `.clear` on the next read
    /// (H19). Asserted here rather than only through `NSColor`, where producing an
    /// extended-range component takes a real colour space and a real display.
    func testClampingComponentsStayInRange() {
        let clamped = RGBA8(clampingRed: 1.4, green: -0.3, blue: 0.5, alpha: 1)
        XCTAssertEqual(clamped, RGBA8(red: 255, green: 0, blue: 128))
        XCTAssertEqual(clamped.hexString, "#FF0080")
        XCTAssertNotNil(RGBA8(hex: clamped.hexString), "a clamped colour must re-parse")
    }

    // MARK: The NSColor / Color bridge

    #if canImport(AppKit)
    func testNSColorParsesSixDigitHex() {
        let red = NSColor(hex: "#FF0000")
        XCTAssertNotNil(red)
        let srgb = red!.usingColorSpace(.sRGB)!
        XCTAssertEqual(srgb.redComponent, 1, accuracy: 0.01)
        XCTAssertEqual(srgb.greenComponent, 0, accuracy: 0.01)
        XCTAssertEqual(srgb.blueComponent, 0, accuracy: 0.01)
    }

    func testNSColorCarriesAlphaThrough() {
        let color = NSColor(hex: "#abcd")
        XCTAssertNotNil(color)
        let srgb = color!.usingColorSpace(.sRGB)!
        XCTAssertEqual(srgb.redComponent, CGFloat(0xAA) / 255, accuracy: 0.001)
        XCTAssertEqual(srgb.greenComponent, CGFloat(0xBB) / 255, accuracy: 0.001)
        XCTAssertEqual(srgb.blueComponent, CGFloat(0xCC) / 255, accuracy: 0.001)
        XCTAssertEqual(srgb.alphaComponent, CGFloat(0xDD) / 255, accuracy: 0.001)
    }

    /// The bridge has to survive the round trip, not just each half: this is what
    /// catches a conversion that loses precision between `RGBA8` and a live colour.
    func testNSColorHexStringRoundTrip() {
        XCTAssertEqual(NSColor(hex: "#3A7BD5")!.hexString, "#3A7BD5")
        XCTAssertEqual(NSColor(hex: "#3A7BD580")!.hexString, "#3A7BD580")
        XCTAssertEqual(NSColor(hex: "#3A7BD5FF")!.hexString, "#3A7BD5")
        XCTAssertNil(NSColor(hex: "+ABCDEF"))
    }

    func testSwiftUIColorBridging() {
        XCTAssertEqual(Color(hexString: "#0A84FF").hexString, "#0A84FF")
    }
    #endif
}
