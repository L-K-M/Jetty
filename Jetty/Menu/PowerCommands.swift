import Foundation
import AppKit
import Darwin   // dlopen / dlsym / dlclose for the isolated loginwindow lock symbol

/// The power / session commands offered in the Jetty Menu's bottom row. The
/// command → action mapping is a pure, unit-tested value; execution is a thin,
/// GUI-session-only runner. Destructive commands are flagged so the UI can confirm
/// first. See PLAN.md §8.2.
enum PowerCommand: String, CaseIterable, Identifiable {
    case sleep
    case lockScreen
    case logOut
    case restart
    case shutDown
    case emptyTrash

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sleep: return "Sleep"
        case .lockScreen: return "Lock Screen"
        case .logOut: return "Log Out"
        case .restart: return "Restart"
        case .shutDown: return "Shut Down"
        case .emptyTrash: return "Empty Trash"
        }
    }

    var systemSymbol: String {
        switch self {
        case .sleep: return "moon.fill"
        case .lockScreen: return "lock.fill"
        case .logOut: return "rectangle.portrait.and.arrow.right"
        case .restart: return "arrow.clockwise.circle.fill"
        case .shutDown: return "power"
        case .emptyTrash: return "trash.fill"
        }
    }

    /// Whether to ask "are you sure?" before running (irreversible / disruptive).
    var isDestructive: Bool {
        switch self {
        case .restart, .shutDown, .logOut, .emptyTrash: return true
        case .sleep, .lockScreen: return false
        }
    }

    /// The properly worded confirmation question shown before a destructive command
    /// runs. Written per command (not derived from `title`) so the article and
    /// casing read naturally — "empty the Trash", not "empty trash" (M35).
    var confirmationPrompt: String {
        switch self {
        case .sleep: return "Are you sure you want to put your Mac to sleep?"
        case .lockScreen: return "Are you sure you want to lock the screen?"
        case .logOut: return "Are you sure you want to log out?"
        case .restart: return "Are you sure you want to restart your Mac?"
        case .shutDown: return "Are you sure you want to shut down your Mac?"
        case .emptyTrash: return "Are you sure you want to empty the Trash?"
        }
    }

    /// The AppleScript that performs the command, or `nil` for commands handled by a
    /// direct API/CLI (`lockScreen`). Pure — this is the bit unit tests assert on.
    var appleScript: String? {
        switch self {
        case .sleep:      return #"tell application "System Events" to sleep"#
        case .logOut:     return #"tell application "System Events" to log out"#
        case .restart:    return #"tell application "System Events" to restart"#
        case .shutDown:   return #"tell application "System Events" to shut down"#
        case .emptyTrash:
            // `ignoring application responses`: return as soon as Finder accepts the
            // command, not when the (possibly minutes-long) delete finishes — so the
            // runner's serial queue is freed immediately and a later power command
            // isn't stuck behind a big empty. Finder still shows its own progress UI.
            return """
                ignoring application responses
                    tell application "Finder" to empty the trash
                end ignoring
                """
        case .lockScreen: return nil
        }
    }
}

/// Executes a `PowerCommand`. Requires a real GUI session (and, for the
/// AppleScript-backed commands, the one-time Automation permission for System
/// Events / Finder).
enum PowerCommandRunner {

    static func run(_ command: PowerCommand) {
        // Exhaustive over the enum on purpose (M35): adding a new command is a
        // compile error here until its execution path is written — no more
        // silently-do-nothing `default`.
        switch command {
        case .sleep, .logOut, .restart, .shutDown, .emptyTrash:
            // AppleScript-backed (mapping is unit-tested). The send blocks until the
            // target app replies, so it runs off the main thread on the shared serial
            // queue — running it on main froze the whole UI while Finder emptied a
            // full Trash. The event still originates from the Jetty process, so the
            // existing Automation (TCC) grant applies unchanged. Fire-and-forget:
            // both call sites already ignore the result and failures are only logged.
            if let script = command.appleScript {
                AppleScriptRunner.runAsync(script)
            } else {
                assertionFailure("PowerCommand \(command) has no AppleScript")
            }
        case .lockScreen:
            // Not AppleScript; SACLockScreenImmediate signals loginwindow and returns
            // instantly (and the screen-saver fallback only spawns a process), so it
            // stays on the caller's thread.
            lockScreen()
        }
    }

    /// Locks the screen. The public options (display sleep, screen saver) only lock
    /// when "Require password" is set to *immediately* — with the common "after
    /// 5 minutes" setting the screen went dark **unlocked** under a button labeled
    /// "Lock Screen". loginwindow's `SACLockScreenImmediate` is what ⌃⌘Q uses and
    /// always locks; per AGENTS.md it's kept isolated, user-invoked, and fail-closed
    /// (dlopen/dlsym like the MediaRemote bridge), falling back to starting the
    /// screen saver — which at least honors the user's password-delay setting and
    /// visibly reacts — if the symbol ever disappears.
    private static func lockScreen() {
        typealias LockFunction = @convention(c) () -> Int32
        let path = "/System/Library/PrivateFrameworks/login.framework/Versions/Current/login"
        if let handle = dlopen(path, RTLD_LAZY) {
            defer { dlclose(handle) }
            if let symbol = dlsym(handle, "SACLockScreenImmediate") {
                let lock = unsafeBitCast(symbol, to: LockFunction.self)
                _ = lock()
                return
            }
        }
        startScreenSaver()
    }

    /// Fallback lock: launch the screen-saver engine (locks per the user's
    /// "require password after screen saver begins" setting).
    private static func startScreenSaver() {
        let engine = "/System/Library/CoreServices/ScreenSaverEngine.app/Contents/MacOS/ScreenSaverEngine"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: engine)
        do { try process.run() } catch { NSLog("Jetty: lockScreen fallback failed: \(error.localizedDescription)") }
    }
}
