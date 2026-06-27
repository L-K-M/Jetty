import SwiftUI

/// General settings: launch at login, system-Dock management, positioning, and the
/// auto-hide / reveal behavior. Positioning (edge × alignment × offset × inset) is
/// Jetty's headline win over the real Dock. See PLAN.md §5, §10.
struct GeneralView: View {
    @ObservedObject var preferences: Preferences
    let systemDock: SystemDockController

    var body: some View {
        Form {
            Section("Startup") {
                Toggle("Launch Jetty at login", isOn: $preferences.launchAtLogin)
            }

            Section("System Dock") {
                Toggle("Hide the macOS Dock while Jetty runs", isOn: $preferences.manageSystemDock)
                Text("Jetty can't remove Apple's Dock (no app can), so it hides it with auto-hide and a long reveal delay. Mission Control and minimize keep working. Use Restore if anything looks off.")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Restore System Dock") { systemDock.restoreSystemDock() }
            }

            Section("Position") {
                Picker("Edge", selection: $preferences.edge) {
                    ForEach(DockEdge.allCases) { Text($0.label).tag($0) }
                }
                Picker("Alignment", selection: $preferences.alignment) {
                    ForEach(DockAlignment.allCases) { Text($0.label).tag($0) }
                }
                HStack {
                    Text("Offset")
                    Slider(value: $preferences.offset, in: -600...600)
                    Text("\(Int(preferences.offset))").monospacedDigit().frame(width: 44, alignment: .trailing)
                }
                HStack {
                    Text("Edge inset")
                    Slider(value: $preferences.inset, in: 0...80)
                    Text("\(Int(preferences.inset))").monospacedDigit().frame(width: 44, alignment: .trailing)
                }
                Picker("Show on", selection: $preferences.displayScope) {
                    ForEach(DisplayScope.allCases) { Text($0.label).tag($0) }
                }
            }

            Section("Behavior") {
                Toggle("Auto-hide the dock", isOn: $preferences.autoHide)
                Picker("Reveal with", selection: $preferences.revealTrigger) {
                    ForEach(RevealTrigger.allCases) { Text($0.label).tag($0) }
                }
                .disabled(!preferences.autoHide)
                HStack {
                    Text("Reveal delay")
                    Slider(value: $preferences.revealDelayMs, in: 0...600)
                    Text("\(Int(preferences.revealDelayMs)) ms").monospacedDigit().frame(width: 64, alignment: .trailing)
                }
                .disabled(!preferences.autoHide)
                HStack {
                    Text("Hide delay")
                    Slider(value: $preferences.hideDelayMs, in: 0...1500)
                    Text("\(Int(preferences.hideDelayMs)) ms").monospacedDigit().frame(width: 64, alignment: .trailing)
                }
                .disabled(!preferences.autoHide)
                Toggle("Show running apps that aren't pinned", isOn: $preferences.showRunningApps)
            }
        }
        .formStyle(.grouped)
    }
}
