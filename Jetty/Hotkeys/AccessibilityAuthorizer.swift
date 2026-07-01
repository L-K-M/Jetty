import ApplicationServices
import AppKit

/// Thin wrapper around the Accessibility (AX) trust APIs.
///
/// Jetty's **core dock needs no permission**. This is used only by the *later*,
/// opt-in window-management features (per-app window lists, click-to-raise,
/// minimize/restore), and by the Permissions settings pane to report status.
enum AccessibilityAuthorizer {

    /// Whether the process is currently trusted for Accessibility.
    static var isTrusted: Bool {
        AXIsProcessTrusted()
    }

    /// Prompts the user to grant Accessibility access (shows the system dialog
    /// the first time). Returns the current trust state.
    @discardableResult
    static func prompt() -> Bool {
        // Value of `kAXTrustedCheckOptionPrompt`; used as a literal to avoid
        // cross-SDK differences in how that symbol is imported into Swift.
        let promptKey = "AXTrustedCheckOptionPrompt"
        let options = [promptKey: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    /// Opens the Accessibility pane in System Settings.
    static func openSystemSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else { return }
        NSWorkspace.shared.open(url)
    }
}
