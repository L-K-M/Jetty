import Foundation
import AppKit

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

    /// The AppleScript that performs the command, or `nil` for commands handled by a
    /// direct API/CLI (`lockScreen`). Pure — this is the bit unit tests assert on.
    var appleScript: String? {
        switch self {
        case .sleep:      return #"tell application "System Events" to sleep"#
        case .logOut:     return #"tell application "System Events" to log out"#
        case .restart:    return #"tell application "System Events" to restart"#
        case .shutDown:   return #"tell application "System Events" to shut down"#
        case .emptyTrash: return #"tell application "Finder" to empty the trash"#
        case .lockScreen: return nil
        }
    }
}

/// Executes a `PowerCommand`. Requires a real GUI session (and, for the
/// AppleScript-backed commands, the one-time Automation permission for System
/// Events / Finder).
enum PowerCommandRunner {

    static func run(_ command: PowerCommand) {
        if let script = command.appleScript {
            runAppleScript(script)
        } else {
            switch command {
            case .lockScreen: lockScreen()
            default: break
            }
        }
    }

    private static func runAppleScript(_ source: String) {
        var error: NSDictionary?
        if let script = NSAppleScript(source: source) {
            script.executeAndReturnError(&error)
            if let error { NSLog("Jetty: power command AppleScript failed: \(error)") }
        }
    }

    /// Locks the screen by putting the display to sleep (requires "Require password
    /// after sleep" to actually lock — the standard public approach).
    private static func lockScreen() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        process.arguments = ["displaysleepnow"]
        do { try process.run() } catch { NSLog("Jetty: lockScreen failed: \(error.localizedDescription)") }
    }
}
