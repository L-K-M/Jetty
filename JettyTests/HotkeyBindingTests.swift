import XCTest
import Carbon.HIToolbox
@testable import Jetty

final class HotkeyBindingTests: XCTestCase {

    func testDefaultsAreValidAndDisplayCorrectly() {
        XCTAssertTrue(HotkeyBinding.defaultToggle.isValid)
        XCTAssertEqual(HotkeyBinding.defaultToggle.displayString, "⌃⌥⌘D")
        XCTAssertEqual(HotkeyBinding.defaultMenu.displayString, "⌃⌥⌘Space")
    }

    func testModifierSymbolsAreInCanonicalOrder() {
        let b = HotkeyBinding(keyCode: 0,
                              modifiers: UInt32(cmdKey | controlKey | optionKey | shiftKey),
                              keyLabel: "A", enabled: true)
        XCTAssertEqual(b.modifierSymbols, "⌃⌥⇧⌘")
    }

    func testIsInvalidWithoutModifiersOrWhenDisabled() {
        let noMods = HotkeyBinding(keyCode: 1, modifiers: 0, keyLabel: "S", enabled: true)
        XCTAssertFalse(noMods.isValid)
        let disabled = HotkeyBinding(keyCode: 2, modifiers: UInt32(cmdKey), keyLabel: "D", enabled: false)
        XCTAssertFalse(disabled.isValid)
    }

    func testJSONRoundTrip() {
        let original = HotkeyBinding(keyCode: 49, modifiers: UInt32(cmdKey | optionKey),
                                     keyLabel: "Space", enabled: true)
        let decoded = HotkeyBinding.decode(original.jsonString, fallback: .defaultMenu)
        XCTAssertEqual(decoded, original)
    }

    func testDecodeFallsBackOnGarbage() {
        XCTAssertEqual(HotkeyBinding.decode("not json", fallback: .defaultToggle), .defaultToggle)
        XCTAssertEqual(HotkeyBinding.decode(nil, fallback: .defaultToggle), .defaultToggle)
    }

    func testCarbonModifiersMapping() {
        let mods = HotkeyBinding.carbonModifiers(from: [.command, .shift])
        XCTAssertEqual(mods & UInt32(cmdKey), UInt32(cmdKey))
        XCTAssertEqual(mods & UInt32(shiftKey), UInt32(shiftKey))
        XCTAssertEqual(mods & UInt32(controlKey), 0)
    }
}
