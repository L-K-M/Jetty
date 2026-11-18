import XCTest
@testable import Jetty

// Carbon modifier bits, spelled as literals: Keycap owns the constants now, and
// these tests deliberately avoid adding a package dependency to the test target.
// The numbers are a persisted storage format — `HotkeyBinding.modifiers` is
// stored as JSON in `UserDefaults` — so they are stable.
private let command: UInt32 = 0x0100
private let shift: UInt32 = 0x0200
private let option: UInt32 = 0x0800
private let control: UInt32 = 0x1000

final class HotkeyBindingTests: XCTestCase {

    func testDefaultsAreValidAndDisplayCorrectly() {
        XCTAssertTrue(HotkeyBinding.defaultToggle.isValid)
        XCTAssertEqual(HotkeyBinding.defaultToggle.displayString, "⌃⌥⌘D")
        XCTAssertEqual(HotkeyBinding.defaultMenu.displayString, "⌃⌥⌘Space")
    }

    func testModifierSymbolsAreInCanonicalOrder() {
        let b = HotkeyBinding(keyCode: 0,
                              modifiers: command | control | option | shift,
                              keyLabel: "A", enabled: true)
        XCTAssertEqual(b.modifierSymbols, "⌃⌥⇧⌘")
    }

    func testIsInvalidWithoutModifiersOrWhenDisabled() {
        let noMods = HotkeyBinding(keyCode: 1, modifiers: 0, keyLabel: "S", enabled: true)
        XCTAssertFalse(noMods.isValid)
        let disabled = HotkeyBinding(keyCode: 2, modifiers: command, keyLabel: "D", enabled: false)
        XCTAssertFalse(disabled.isValid)
    }

    func testJSONRoundTrip() {
        let original = HotkeyBinding(keyCode: 49, modifiers: command | option,
                                     keyLabel: "Space", enabled: true)
        let decoded = HotkeyBinding.decode(original.jsonString, fallback: .defaultMenu)
        XCTAssertEqual(decoded, original)
    }

    func testDecodeFallsBackOnGarbage() {
        XCTAssertEqual(HotkeyBinding.decode("not json", fallback: .defaultToggle), .defaultToggle)
        XCTAssertEqual(HotkeyBinding.decode(nil, fallback: .defaultToggle), .defaultToggle)
    }
}
