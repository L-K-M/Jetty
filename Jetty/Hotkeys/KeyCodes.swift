import Carbon.HIToolbox

/// Virtual key codes and Carbon modifier flags used by Jetty's optional global
/// hotkeys (US layout, position-based).
enum KeyCode {
    static let escape: UInt32 = UInt32(kVK_Escape)   // 53
    static let space: UInt32 = UInt32(kVK_Space)     // 49
    static let `return`: UInt32 = UInt32(kVK_Return) // 36
    static let d: UInt32 = UInt32(kVK_ANSI_D)        // 2
    static let j: UInt32 = UInt32(kVK_ANSI_J)        // 38

    /// Carbon modifier-flag bits for `RegisterEventHotKey`.
    enum Modifier {
        static let command = UInt32(cmdKey)
        static let option = UInt32(optionKey)
        static let control = UInt32(controlKey)
        static let shift = UInt32(shiftKey)
    }
}
