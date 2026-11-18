// Foundation is unconditional: the persistence half below needs it on every platform,
// and `JSONEncoder`/`JSONDecoder` are top-level names, so file-scoped lookup really
// does require it here — without this import they are not in scope (measured).
import Foundation
#if canImport(AppKit)
// KeycapKit re-exports KeycapCore, so one import covers the chord model used
// below; Keycap's `NSEvent`-based recorder helpers live in Keycap itself.
import KeycapKit
#else
import KeycapCore
#endif

/// A user-configurable global hotkey: a virtual key code plus Carbon modifier
/// flags, an on/off switch, and a human label captured at record time (so the
/// display respects the user's keyboard layout without a keycode→name table).
/// Persisted as JSON in `UserDefaults`; registered via Keycap's `CarbonHotkey`
/// (which needs no permission). See MF-6 / PLAN.md §8.2.
struct HotkeyBinding: Codable, Equatable {
    var keyCode: UInt32
    /// Carbon modifier-flag bits (`cmdKey | optionKey | …`).
    var modifiers: UInt32
    /// The key's display label, e.g. `"D"`, `"Space"`, `"↩"`.
    var keyLabel: String
    var enabled: Bool

    /// The Keycap chord this binding persists. Keycap owns the key-code and
    /// modifier literals; the four stored fields above stay the storage format.
    var combo: KeyCombo {
        KeyCombo(keyCode: keyCode, modifiers: HotkeyModifiers(carbonFlags: modifiers))
    }

    /// Registerable only when enabled and a usable global hotkey: not
    /// system-reserved, and either carrying ⌘/⌃/⌥ or a bare function key.
    /// Shift alone is not enough — it only changes the typed character.
    var isValid: Bool { enabled && combo.isUsableGlobalHotkey }

    /// The modifier glyphs in canonical macOS order (⌃⌥⇧⌘).
    var modifierSymbols: String { combo.modifiers.symbols }

    /// The full shortcut, e.g. `"⌃⌥⌘D"`.
    var displayString: String { combo.displayString(keyName: keyLabel) }

    // MARK: Persistence

    /// Decodes a binding from its stored JSON string, or returns `fallback`.
    static func decode(_ json: String?, fallback: HotkeyBinding) -> HotkeyBinding {
        guard let json, let data = json.data(using: .utf8),
              let value = try? JSONDecoder().decode(HotkeyBinding.self, from: data) else { return fallback }
        return value
    }

    /// Encodes the binding to a JSON string for `UserDefaults`.
    var jsonString: String {
        (try? JSONEncoder().encode(self)).flatMap { String(data: $0, encoding: .utf8) } ?? ""
    }

    // MARK: Defaults

    private static let defaultModifiers: UInt32 =
        HotkeyModifiers.control.rawValue | HotkeyModifiers.option.rawValue | HotkeyModifiers.command.rawValue

    static let defaultToggle = HotkeyBinding(keyCode: KeyCode.d, modifiers: defaultModifiers,
                                             keyLabel: "D", enabled: true)
    static let defaultMenu = HotkeyBinding(keyCode: KeyCode.space, modifiers: defaultModifiers,
                                           keyLabel: "Space", enabled: true)
}
