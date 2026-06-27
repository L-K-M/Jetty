import SwiftUI

/// Settings/help for the Jetty Menu (the Start-menu-style launcher). See PLAN.md §8.2.
struct MenuView: View {
    @ObservedObject var preferences: Preferences

    var body: some View {
        Form {
            Section("Jetty Menu") {
                Text("A fast launcher with app search and power commands. Open it from its dock tile, the menu-bar item\(menuShortcutSuffix). Change the shortcut under General ▸ Shortcuts.")
                    .font(.callout).foregroundStyle(.secondary)
            }

            Section("Power commands") {
                ForEach(PowerCommand.allCases) { command in
                    Label {
                        Text(command.title)
                        if command.isDestructive {
                            Text("· asks for confirmation").font(.caption).foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: command.systemSymbol)
                    }
                }
                Text("Sleep / Restart / Shut Down / Log Out are sent to System Events, so the first use prompts for Automation permission. Lock Screen sleeps the display (set “Require password after sleep” to lock).")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Info tiles") {
                Text("The clock, world clock, Pomodoro, weather, and other live tiles are configured under the Widgets tab.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var menuShortcutSuffix: String {
        preferences.menuHotkey.isValid ? ", or the global shortcut \(preferences.menuHotkey.displayString)" : ""
    }
}
