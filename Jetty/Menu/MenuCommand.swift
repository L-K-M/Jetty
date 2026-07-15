import Foundation

/// Quick system toggles surfaced in the Jetty Menu command bar (ND-9). Matching the
/// query against keywords is pure (unit-tested); running uses AppleScript (System
/// Events), so the first use prompts for Automation permission.
enum MenuCommand: String, CaseIterable, Identifiable {
    case toggleDarkMode

    var id: String { rawValue }

    var title: String {
        switch self {
        case .toggleDarkMode: return "Toggle Dark Mode"
        }
    }

    var symbol: String {
        switch self {
        case .toggleDarkMode: return "circle.lefthalf.filled"
        }
    }

    var keywords: [String] {
        switch self {
        case .toggleDarkMode: return ["dark mode", "dark", "darkmode", "light mode", "appearance"]
        }
    }

    var appleScript: String {
        switch self {
        case .toggleDarkMode:
            return #"tell application "System Events" to tell appearance preferences to set dark mode to not dark mode"#
        }
    }

    /// The command whose keywords match the query, or `nil`. Needs ≥4 chars and matches
    /// only when the query is a **prefix of a keyword** — not the other way round. The
    /// old bidirectional `q.hasPrefix($0)` meant any query *starting with* a keyword
    /// matched forever, so "darkroom" (a real app) or "appearances" could never launch
    /// or reach web search — the command hijacked Return permanently (F-H4). Pure.
    static func match(_ query: String) -> MenuCommand? {
        let q = query.lowercased().trimmingCharacters(in: .whitespaces)
        guard q.count >= 4 else { return nil }
        return allCases.first { command in
            command.keywords.contains { $0.hasPrefix(q) }
        }
    }

    /// Runs the command (AppleScript via System Events). Off the main thread on the
    /// shared serial queue — like the power commands, the send blocks until System
    /// Events replies (and the first use blocks on the Automation prompt), which on
    /// the main thread would freeze the UI.
    static func run(_ command: MenuCommand) {
        AppleScriptRunner.runAsync(command.appleScript)
    }
}
