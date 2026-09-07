#if canImport(AppKit)
import AppKit
#endif
#if canImport(Carbon)
import Carbon.HIToolbox
#else
import Foundation
#endif

/// A user-configurable global hotkey: a virtual key code plus Carbon modifier
/// flags, an on/off switch, and a human label captured at record time (so the
/// display respects the user's keyboard layout without a keycode→name table).
/// Persisted as JSON in `UserDefaults`; registered via `CarbonHotkey` (which needs
/// no permission). See MF-6 / PLAN.md §8.2.
struct HotkeyBinding: Codable, Equatable {
    var keyCode: UInt32
    /// Carbon modifier-flag bits (`cmdKey | optionKey | …`).
    var modifiers: UInt32
    /// The key's display label, e.g. `"D"`, `"Space"`, `"↩"`.
    var keyLabel: String
    var enabled: Bool

    /// Registerable only when enabled and carrying at least one modifier — a bare
    /// key would steal that key system-wide.
    var isValid: Bool { enabled && modifiers != 0 }

    // MARK: The stored bit values

    /// The Carbon modifier bits, named. These are not a Carbon detail to look up at
    /// the call site: `modifiers` is **persisted** as JSON in `UserDefaults`, so the
    /// numbers are part of a storage format every build has to agree on — the same
    /// argument that pulled `RGBA8` out of `NSColor` in JP-04. Naming them here is
    /// also what lets this type exist off Darwin, where `Carbon.HIToolbox` does not.
    ///
    /// `HotkeyBindingTests` asserts on Darwin that each equals the Carbon symbol it
    /// mirrors, so a wrong value fails the build's own tests rather than silently
    /// rewriting users' stored hotkeys.
    enum Modifier {
        static let command: UInt32 = 0x0100
        static let shift: UInt32 = 0x0200
        static let option: UInt32 = 0x0800
        static let control: UInt32 = 0x1000
    }

    /// Virtual key codes for the shipped defaults, for the same reason.
    enum KeyCode {
        static let d: UInt32 = 0x02
        static let space: UInt32 = 0x31
    }

    /// The modifier glyphs in canonical macOS order (⌃⌥⇧⌘).
    var modifierSymbols: String {
        var s = ""
        if modifiers & Modifier.control != 0 { s += "⌃" }
        if modifiers & Modifier.option  != 0 { s += "⌥" }
        if modifiers & Modifier.shift   != 0 { s += "⇧" }
        if modifiers & Modifier.command != 0 { s += "⌘" }
        return s
    }

    /// The full shortcut, e.g. `"⌃⌥⌘D"`.
    var displayString: String { modifierSymbols + keyLabel }

    // MARK: Capture

    // Recording a hotkey means reading an `NSEvent`, so this half is Darwin's. The
    // stored form above, and the encode/decode below it, are not.
    #if canImport(AppKit)

    /// Builds a binding from a recorded key event (preserving the current `enabled`).
    func updated(from event: NSEvent) -> HotkeyBinding {
        HotkeyBinding(keyCode: UInt32(event.keyCode),
                      modifiers: Self.carbonModifiers(from: event.modifierFlags),
                      keyLabel: Self.label(for: event),
                      enabled: enabled)
    }

    /// Maps Cocoa modifier flags to Carbon's `RegisterEventHotKey` bits.
    static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var carbon: UInt32 = 0
        if flags.contains(.command) { carbon |= UInt32(cmdKey) }
        if flags.contains(.option)  { carbon |= UInt32(optionKey) }
        if flags.contains(.control) { carbon |= UInt32(controlKey) }
        if flags.contains(.shift)   { carbon |= UInt32(shiftKey) }
        return carbon
    }

    /// A short label for a recorded key, using the layout-aware character when the
    /// key isn't one of the named special keys.
    static func label(for event: NSEvent) -> String {
        switch Int(event.keyCode) {
        case kVK_Space:       return "Space"
        case kVK_Return, kVK_ANSI_KeypadEnter: return "↩"
        case kVK_Tab:         return "⇥"
        case kVK_Delete:      return "⌫"
        case kVK_ForwardDelete: return "⌦"
        case kVK_Escape:      return "⎋"
        case kVK_LeftArrow:   return "←"
        case kVK_RightArrow:  return "→"
        case kVK_UpArrow:     return "↑"
        case kVK_DownArrow:   return "↓"
        case kVK_Home:        return "↖"
        case kVK_End:         return "↘"
        case kVK_PageUp:      return "⇞"
        case kVK_PageDown:    return "⇟"
        default:
            if let chars = event.charactersIgnoringModifiers, !chars.isEmpty,
               chars.first.map({ !$0.isWhitespace }) == true {
                return chars.uppercased()
            }
            return "Key \(event.keyCode)"
        }
    }

    #endif

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

    static let defaultToggle = HotkeyBinding(keyCode: KeyCode.d,
                                             modifiers: Modifier.control | Modifier.option | Modifier.command,
                                             keyLabel: "D", enabled: true)
    static let defaultMenu = HotkeyBinding(keyCode: KeyCode.space,
                                           modifiers: Modifier.control | Modifier.option | Modifier.command,
                                           keyLabel: "Space", enabled: true)
}
