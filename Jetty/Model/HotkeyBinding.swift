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

    /// The modifier glyphs in canonical macOS order (⌃⌥⇧⌘).
    var modifierSymbols: String {
        var s = ""
        if modifiers & KeyCode.Modifier.control != 0 { s += "⌃" }
        if modifiers & KeyCode.Modifier.option  != 0 { s += "⌥" }
        if modifiers & KeyCode.Modifier.shift   != 0 { s += "⇧" }
        if modifiers & KeyCode.Modifier.command != 0 { s += "⌘" }
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
        if flags.contains(.command) { carbon |= KeyCode.Modifier.command }
        if flags.contains(.option)  { carbon |= KeyCode.Modifier.option }
        if flags.contains(.control) { carbon |= KeyCode.Modifier.control }
        if flags.contains(.shift)   { carbon |= KeyCode.Modifier.shift }
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

    private static let defaultModifiers =
        KeyCode.Modifier.control | KeyCode.Modifier.option | KeyCode.Modifier.command

    static let defaultToggle = HotkeyBinding(keyCode: KeyCode.d, modifiers: defaultModifiers,
                                             keyLabel: "D", enabled: true)
    static let defaultMenu = HotkeyBinding(keyCode: KeyCode.space, modifiers: defaultModifiers,
                                           keyLabel: "Space", enabled: true)
}
