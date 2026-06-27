import XCTest
import AppKit
import SwiftUI
@testable import Jetty

final class ColorHexTests: XCTestCase {

    func testParsesSixDigitHex() {
        let red = NSColor(hex: "#FF0000")
        XCTAssertNotNil(red)
        let srgb = red!.usingColorSpace(.sRGB)!
        XCTAssertEqual(srgb.redComponent, 1, accuracy: 0.01)
        XCTAssertEqual(srgb.greenComponent, 0, accuracy: 0.01)
        XCTAssertEqual(srgb.blueComponent, 0, accuracy: 0.01)
    }

    func testLeadingHashOptional() {
        XCTAssertNotNil(NSColor(hex: "00FF00"))
    }

    func testInvalidReturnsNil() {
        XCTAssertNil(NSColor(hex: "nothex"))
        XCTAssertNil(NSColor(hex: "#FFF"))   // 3-digit not supported
    }

    func testHexStringRoundTrip() {
        XCTAssertEqual(NSColor(hex: "#3A7BD5")!.hexString, "#3A7BD5")
    }

    func testSwiftUIColorBridging() {
        XCTAssertEqual(Color(hexString: "#0A84FF").hexString, "#0A84FF")
    }
}
