import XCTest
@testable import Jetty

final class SemanticVersionTests: XCTestCase {

    func testParsesAndCompares() {
        XCTAssertTrue(SemanticVersion("1.2.3")! > SemanticVersion("1.2.0")!)
        XCTAssertTrue(SemanticVersion("2.0.0")! > SemanticVersion("1.9.9")!)
    }

    func testLeadingVAndPadding() {
        XCTAssertEqual(SemanticVersion("v1.2")!, SemanticVersion("1.2.0")!)
    }

    func testPrereleaseSortsBelowRelease() {
        XCTAssertTrue(SemanticVersion("1.2.0-beta")! < SemanticVersion("1.2.0")!)
    }

    func testPrereleaseUsesSemVerIdentifierOrdering() {
        XCTAssertTrue(SemanticVersion("1.2.0-beta.2")! < SemanticVersion("1.2.0-beta.10")!)
        XCTAssertTrue(SemanticVersion("1.2.0-1")! < SemanticVersion("1.2.0-alpha")!)
        XCTAssertTrue(SemanticVersion("1.2.0-alpha")! < SemanticVersion("1.2.0-alpha.1")!)
        XCTAssertTrue(SemanticVersion("1.2.0-alpha.1")! < SemanticVersion("1.2.0-alpha.beta")!)
    }

    func testRejectsNonNumeric() {
        XCTAssertNil(SemanticVersion("latest"))
        XCTAssertNil(SemanticVersion(""))
    }
}
