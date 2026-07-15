import Foundation

/// Runs Jetty's AppleScript-backed actions — the power/session commands and the
/// quick menu toggles — off the main thread.
///
/// `NSAppleScript.executeAndReturnError` performs a *synchronous* Apple Event send
/// that blocks the calling thread until the target app replies. On the main thread
/// that froze the whole UI: emptying a full Trash beachballed Jetty until Finder
/// finished deleting (it looked like a crash). Every send therefore goes through
/// `runAsync`, onto one serial background queue.
///
/// The queue MUST stay *serial*. `NSAppleScript` is not safe for simultaneous use
/// from multiple threads — even separate instances share process-global OSA state —
/// so two `executeAndReturnError` calls must never overlap. This is the single
/// shared queue for *every* caller (both `PowerCommandRunner` and `MenuCommand`)
/// precisely so they can't run on two threads at once. Do NOT switch it to a
/// concurrent queue and do NOT add a second queue.
enum AppleScriptRunner {

    private static let queue = DispatchQueue(
        label: "com.jettyapp.Jetty.AppleScript",
        qos: .userInitiated)

    /// Compiles and sends `source` on the serial background queue, logging any
    /// failure. Fire-and-forget: callers don't inspect completion (failures were
    /// only ever logged). A fresh `NSAppleScript` is created and consumed entirely
    /// inside the work item, so no instance is shared across threads.
    static func runAsync(_ source: String) {
        queue.async {
            var error: NSDictionary?
            NSAppleScript(source: source)?.executeAndReturnError(&error)
            if let error { NSLog("Jetty: AppleScript failed: \(error)") }
        }
    }

    /// Primes AppleScript / XProtect initialization on the main thread, once, at
    /// launch. On macOS 26 the *first* `NSAppleScript` execution kicks off XProtect
    /// malware-evaluation init that `dispatch_sync`s to the main queue; if that first
    /// call lands on a background thread while the main thread is busy, it can
    /// deadlock — reintroducing the very freeze this indirection removes. Running a
    /// trivial script here does the init inline on the main thread (safe: when
    /// already on main it runs inline, never a self-`dispatch_sync`), so every later
    /// background send is safe. The bare `return` script triggers the OSA/XProtect
    /// init without sending an Apple Event, so it never prompts for Automation.
    /// Call on the main thread during app startup.
    static func warmUp() {
        _ = NSAppleScript(source: "return")?.executeAndReturnError(nil)
    }
}
