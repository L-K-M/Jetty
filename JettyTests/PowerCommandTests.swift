import XCTest
@testable import Jetty

final class PowerCommandTests: XCTestCase {

    func testAppleScriptMapping() {
        XCTAssertEqual(PowerCommand.shutDown.appleScript?.contains("shut down"), true)
        XCTAssertEqual(PowerCommand.restart.appleScript?.contains("restart"), true)
        XCTAssertEqual(PowerCommand.logOut.appleScript?.contains("log out"), true)
        XCTAssertEqual(PowerCommand.sleep.appleScript?.contains("sleep"), true)
        XCTAssertEqual(PowerCommand.emptyTrash.appleScript?.contains("empty the trash"), true)
    }

    func testLockScreenHasNoAppleScript() {
        // Lock is handled by a direct CLI call, not AppleScript.
        XCTAssertNil(PowerCommand.lockScreen.appleScript)
    }

    func testDestructiveFlags() {
        XCTAssertTrue(PowerCommand.shutDown.isDestructive)
        XCTAssertTrue(PowerCommand.restart.isDestructive)
        XCTAssertTrue(PowerCommand.logOut.isDestructive)
        XCTAssertTrue(PowerCommand.emptyTrash.isDestructive)
        XCTAssertFalse(PowerCommand.sleep.isDestructive)
        XCTAssertFalse(PowerCommand.lockScreen.isDestructive)
    }

    func testEveryCommandHasTitleAndSymbol() {
        for command in PowerCommand.allCases {
            XCTAssertFalse(command.title.isEmpty)
            XCTAssertFalse(command.systemSymbol.isEmpty)
        }
    }
}
