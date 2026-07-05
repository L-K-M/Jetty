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

    func testConfirmationPrompts() {
        // Per-command wording (M35) — not derived from `title`, so the article and
        // casing read naturally.
        XCTAssertEqual(PowerCommand.emptyTrash.confirmationPrompt,
                       "Are you sure you want to empty the Trash?")
        XCTAssertEqual(PowerCommand.shutDown.confirmationPrompt,
                       "Are you sure you want to shut down your Mac?")
        XCTAssertEqual(PowerCommand.restart.confirmationPrompt,
                       "Are you sure you want to restart your Mac?")
        XCTAssertEqual(PowerCommand.logOut.confirmationPrompt,
                       "Are you sure you want to log out?")
        XCTAssertEqual(PowerCommand.sleep.confirmationPrompt,
                       "Are you sure you want to put your Mac to sleep?")
        XCTAssertEqual(PowerCommand.lockScreen.confirmationPrompt,
                       "Are you sure you want to lock the screen?")
    }

    func testEveryCommandHasWellFormedConfirmationPrompt() {
        for command in PowerCommand.allCases {
            let prompt = command.confirmationPrompt
            XCTAssertTrue(prompt.hasPrefix("Are you sure you want to "),
                          "\(command) prompt should be a full question: \(prompt)")
            XCTAssertTrue(prompt.hasSuffix("?"),
                          "\(command) prompt should end with a question mark: \(prompt)")
        }
    }
}
