import XCTest
@testable import Jetty

/// Tests for `ItemsView.normalizedLinkURL(from:)` — the "Add a Link" normalization.
/// `host:port` shapes must get `https://` prepended (a naive scheme regex read
/// "localhost" as a scheme, producing a dead tile — FAB-B14), while real hierarchical
/// and known non-hierarchical schemes pass through untouched.
final class LinkNormalizationTests: XCTestCase {

    func testHostPortGetsHTTPSPrepended() {
        XCTAssertEqual(ItemsView.normalizedLinkURL(from: "localhost:3000")?.absoluteString,
                       "https://localhost:3000")
    }

    func testDomainWithPortGetsHTTPSPrepended() {
        XCTAssertEqual(ItemsView.normalizedLinkURL(from: "example.com:8080")?.absoluteString,
                       "https://example.com:8080")
    }

    func testBareDomainGetsHTTPSPrepended() {
        XCTAssertEqual(ItemsView.normalizedLinkURL(from: "example.com")?.absoluteString,
                       "https://example.com")
    }

    func testExplicitHTTPSIsUnchanged() {
        XCTAssertEqual(ItemsView.normalizedLinkURL(from: "https://a.b")?.absoluteString,
                       "https://a.b")
    }

    func testMailtoIsUnchanged() {
        XCTAssertEqual(ItemsView.normalizedLinkURL(from: "mailto:x@y.z")?.absoluteString,
                       "mailto:x@y.z")
    }

    func testTelIsUnchanged() {
        XCTAssertEqual(ItemsView.normalizedLinkURL(from: "tel:+14155551234")?.absoluteString,
                       "tel:+14155551234")
    }

    func testWhitespaceIsTrimmed() {
        XCTAssertEqual(ItemsView.normalizedLinkURL(from: "  example.com  ")?.absoluteString,
                       "https://example.com")
    }

    func testEmptyInputReturnsNil() {
        XCTAssertNil(ItemsView.normalizedLinkURL(from: ""))
        XCTAssertNil(ItemsView.normalizedLinkURL(from: "   "))
    }
}
