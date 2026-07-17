import AppKit
import CoreServices

/// Asks **Finder** how full the Trash is — the only exact Trash-state source that
/// works without Full Disk Access (see TRASH.md). Finder owns the Trash and answers
/// `count items of trash` via AppleEvents, which requires *Automation consent for
/// Finder* (`kTCCServiceAppleEvents/com.apple.finder`).
///
/// Consent is preflighted silently with `AEDeterminePermissionToAutomateTarget`:
/// Jetty only sends passively when the answer is *granted* — a spontaneous consent
/// prompt from a background icon refresh would be unacceptable. The Settings
/// "Request…" path sends user-initiated, where the OS prompt is the point.
enum FinderAutomation {

    enum Status: Equatable {
        /// Consent already granted — passive queries are allowed.
        case granted
        /// The user (or an MDM profile) has denied consent. Asking is pointless.
        case denied
        /// No decision recorded yet — a send would trigger the OS consent prompt,
        /// so it must only happen user-initiated.
        case undetermined
        /// The status could not be determined (unexpected API failure).
        case unknown
    }

    // Apple Event Manager error codes of interest (AE/AERegistry.h); compared as
    // literals so this file doesn't depend on Swift constant availability.
    private static let aeEventNotPermitted: OSStatus = -1744          // errAEEventNotPermitted
    private static let aeEventWouldRequireUserConsent: OSStatus = -1745 // errAEEventWouldRequireUserConsent

    /// Silent consent check for automating Finder. Never prompts.
    static func permissionStatus() -> Status {
        var address = AEAddressDesc()
        var bundleID = Array("com.apple.finder".utf8)
        let created = bundleID.withUnsafeMutableBytes { rawBuffer -> OSErr in
            guard let base = rawBuffer.baseAddress else { return OSErr(-50) }
            return AECreateDesc(DescType(typeApplicationBundleID), base, rawBuffer.count, &address)
        }
        guard created == noErr else { return .unknown }
        switch AEDeterminePermissionToAutomateTarget(&address, AEEventClass(typeWildCard),
                                                     AEEventID(typeWildCard), false) {
        case noErr: return .granted
        case aeEventNotPermitted: return .denied
        case aeEventWouldRequireUserConsent: return .undetermined
        default: return .unknown   // e.g. procNotFound — treat conservatively
        }
    }

    /// The number of items in the Trash according to Finder, or nil on any failure
    /// (no consent, Finder error, unparseable reply). Runs on the shared serial
    /// AppleScript queue; completes on the main queue. Only call this when
    /// `permissionStatus() == .granted` (passive) or from an explicit user action.
    static func trashItemCount(completion: @escaping (Int?) -> Void) {
        AppleScriptRunner.run(#"tell application "Finder" to get (count of items of trash)"#) { result, _ in
            completion(result?.int32Value.map { Int($0) })
        }
    }

    /// User-initiated consent request: sends the query so the OS shows its
    /// "Jetty wants to control Finder" prompt when consent is undetermined.
    /// Completes with the post-prompt status on the main queue.
    static func requestAccess(completion: @escaping (Status) -> Void) {
        trashItemCount { _ in
            // The send itself records the user's decision; re-read it.
            completion(permissionStatus())
        }
    }

    /// Opens System Settings at Privacy & Security → Automation.
    static func openAutomationSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
            NSWorkspace.shared.open(url)
        }
    }
}
