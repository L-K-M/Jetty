import XCTest
import AppKit
@testable import Jetty

final class TrashIconTests: XCTestCase {

    func testDefaultUsesSystemArtworkAndSevenUsesBundledAssets() {
        // `.default` comes from the CoreTypes system can, not a bundled asset; other
        // styles name an asset-catalog empty/full pair.
        XCTAssertNil(TrashIconStyle.default.assetNames)
        XCTAssertEqual(TrashIconStyle.seven.assetNames?.empty, "TrashSevenEmpty")
        XCTAssertEqual(TrashIconStyle.seven.assetNames?.full, "TrashSevenFull")
    }

    func testEveryStyleAndStateResolvesToARealImage() {
        // The provider must never hand the dock a blank/zero-size image — a missing or
        // invalid style asset falls back to the system can.
        XCTAssertFalse(TrashIconStyle.allCases.isEmpty)
        for style in TrashIconStyle.allCases {
            for isFull in [true, false] {
                let icon = TrashIconProvider.icon(isFull: isFull, style: style)
                XCTAssertTrue(icon.isValid, "\(style.rawValue) full=\(isFull) is not a valid image")
                XCTAssertGreaterThan(icon.size.width, 0, "\(style.rawValue) full=\(isFull)")
                XCTAssertGreaterThan(icon.size.height, 0, "\(style.rawValue) full=\(isFull)")
            }
        }
    }

    func testStyleRawValueRoundTrips() {
        for style in TrashIconStyle.allCases {
            XCTAssertEqual(TrashIconStyle(rawValue: style.rawValue), style)
        }
    }
}
