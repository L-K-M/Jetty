#if canImport(Carbon)
import Carbon.HIToolbox
#else
import Foundation
#endif

/// Virtual key codes and Carbon modifier flags used by Jetty's optional global
/// hotkeys (US layout, position-based).
///
/// Spelled as literals rather than derived from `Carbon.HIToolbox`, because these
/// numbers are **persisted**: `HotkeyBinding` stores them as JSON in `UserDefaults`,
/// so they are a storage format every build has to agree on — the same argument that
/// pulled `RGBA8` out of `NSColor` in JP-04. Writing them out is also what lets this
/// file exist off Darwin, where Carbon does not.
///
/// `HotkeyBindingTests.testPortableKeyCodesMatchCarbon` asserts every one of them
/// against the Carbon symbol it mirrors, wherever Carbon exists, so a wrong literal
/// fails the build's own tests rather than silently rewriting users' saved hotkeys.
enum KeyCode {
    static let escape: UInt32 = 53
    static let space: UInt32 = 49
    static let `return`: UInt32 = 36
    static let d: UInt32 = 2
    static let j: UInt32 = 38

    /// Carbon modifier-flag bits for `RegisterEventHotKey`.
    enum Modifier {
        static let command: UInt32 = 0x0100
        static let option: UInt32 = 0x0800
        static let control: UInt32 = 0x1000
        static let shift: UInt32 = 0x0200
    }
}
