import XCTest
#if canImport(Carbon)
import Carbon.HIToolbox
#endif
@testable import Jetty

private typealias Mod = KeyCode.Modifier

final class HotkeyBindingTests: XCTestCase {

    func testDefaultsAreValidAndDisplayCorrectly() {
        XCTAssertTrue(HotkeyBinding.defaultToggle.isValid)
        XCTAssertEqual(HotkeyBinding.defaultToggle.displayString, "⌃⌥⌘D")
        XCTAssertEqual(HotkeyBinding.defaultMenu.displayString, "⌃⌥⌘Space")
    }

    func testModifierSymbolsAreInCanonicalOrder() {
        let b = HotkeyBinding(keyCode: 0,
                              modifiers: Mod.command | Mod.control | Mod.option | Mod.shift,
                              keyLabel: "A", enabled: true)
        XCTAssertEqual(b.modifierSymbols, "⌃⌥⇧⌘")
    }

    func testIsInvalidWithoutModifiersOrWhenDisabled() {
        let noMods = HotkeyBinding(keyCode: 1, modifiers: 0, keyLabel: "S", enabled: true)
        XCTAssertFalse(noMods.isValid)
        let disabled = HotkeyBinding(keyCode: 2, modifiers: Mod.command, keyLabel: "D", enabled: false)
        XCTAssertFalse(disabled.isValid)
    }

    func testJSONRoundTrip() {
        let original = HotkeyBinding(keyCode: 49, modifiers: Mod.command | Mod.option,
                                     keyLabel: "Space", enabled: true)
        let decoded = HotkeyBinding.decode(original.jsonString, fallback: .defaultMenu)
        XCTAssertEqual(decoded, original)
    }

    func testDecodeFallsBackOnGarbage() {
        XCTAssertEqual(HotkeyBinding.decode("not json", fallback: .defaultToggle), .defaultToggle)
        XCTAssertEqual(HotkeyBinding.decode(nil, fallback: .defaultToggle), .defaultToggle)
    }

    /// The portable `Modifier` bits must be exactly Carbon's. They are a persisted
    /// format — `modifiers` is stored as JSON in `UserDefaults` — so if these ever
    /// diverged, every saved hotkey would decode to the wrong chord. Asserted where
    /// Carbon exists, which is the only place the two can be compared.
    #if canImport(Carbon)
    func testPortableKeyCodesMatchCarbon() {
        // Exhaustive by construction: every constant `KeyCodes.swift` defines is pinned
        // below. Keep it that way — a constant that can reach `UserDefaults` without an
        // assertion here is unprotected, and nothing detects that it is missing: Linux
        // cannot compare against Carbon, and Darwin only checks what is written down.
        XCTAssertEqual(Mod.command, UInt32(cmdKey))
        XCTAssertEqual(Mod.shift, UInt32(shiftKey))
        XCTAssertEqual(Mod.option, UInt32(optionKey))
        XCTAssertEqual(Mod.control, UInt32(controlKey))
        XCTAssertEqual(KeyCode.escape, UInt32(kVK_Escape))
        XCTAssertEqual(KeyCode.space, UInt32(kVK_Space))
        XCTAssertEqual(KeyCode.return, UInt32(kVK_Return))
        XCTAssertEqual(KeyCode.d, UInt32(kVK_ANSI_D))
        XCTAssertEqual(KeyCode.j, UInt32(kVK_ANSI_J))
    }
    #endif

    #if canImport(AppKit) && canImport(Carbon)
    func testCarbonModifiersMapping() {
        let mods = HotkeyBinding.carbonModifiers(from: [.command, .shift])
        XCTAssertEqual(mods & UInt32(cmdKey), UInt32(cmdKey))
        XCTAssertEqual(mods & UInt32(shiftKey), UInt32(shiftKey))
        XCTAssertEqual(mods & UInt32(controlKey), 0)
    }
    #endif
}
