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

            Section("Jetty Menu icon") {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 42), spacing: 8)], spacing: 8) {
                    ForEach(JettyMenuGlyph.availableOptions, id: \.self) { symbol in
                        Button { preferences.jettyMenuSymbol = symbol } label: {
                            Image(systemName: symbol)
                                .font(.system(size: 18))
                                .frame(width: 40, height: 40)
                                .background(isSelected(symbol) ? preferences.tintColor.opacity(0.25) : Color.secondary.opacity(0.12),
                                            in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                                        .stroke(isSelected(symbol) ? preferences.tintColor : .clear, lineWidth: 2))
                        }
                        .buttonStyle(.plain)
                        .help(symbol)
                    }
                }
                .padding(.vertical, 4)

                HStack {
                    Text("Custom symbol")
                    TextField("any SF Symbol name", text: $preferences.jettyMenuSymbol)
                        .textFieldStyle(.roundedBorder)
                    Image(systemName: JettyMenuGlyph.resolved(preferences.jettyMenuSymbol))
                        .foregroundStyle(preferences.tintColor)
                        .frame(width: 22)
                }
                Text("Pick an icon above, or type any SF Symbol name (browse them in Apple's free SF Symbols app). Unknown names fall back to the default.")
                    .font(.caption).foregroundStyle(.secondary)
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

    private func isSelected(_ symbol: String) -> Bool {
        preferences.jettyMenuSymbol.trimmingCharacters(in: .whitespacesAndNewlines) == symbol
    }

    private var menuShortcutSuffix: String {
        preferences.menuHotkey.isValid ? ", or the global shortcut \(preferences.menuHotkey.displayString)" : ""
    }
}
