import SwiftUI

/// About + updates pane. Shows the version and wires the GitHub self-updater.
struct AboutView: View {
    @ObservedObject var updateChecker: UpdateChecker

    private var version: String { Bundle.main.shortVersionString }

    var body: some View {
        Form {
            Section {
                HStack(spacing: 14) {
                    Image(systemName: "dock.rectangle")
                        .font(.system(size: 40))
                        .foregroundStyle(.tint)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Jetty").font(.title2).bold()
                        Text("Version \(version)").foregroundStyle(.secondary)
                        Text("A modern, native dock for macOS Tahoe.").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
            }

            Section("Updates") {
                Toggle("Check for updates automatically", isOn: $updateChecker.automaticChecksEnabled)
                HStack {
                    Button("Check Now") { updateChecker.checkNow() }
                        .disabled(updateChecker.isChecking)
                    if updateChecker.isChecking { ProgressView().controlSize(.small) }
                    Spacer()
                    if let date = updateChecker.lastCheckDate {
                        Text("Last checked \(date.formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }

            Section {
                Link("Jetty on GitHub", destination: URL(string: "https://github.com/L-K-M/Jetty")!)
                Text("Part of the L-K-M family alongside Zap (app switcher) and MacDring (edge-tab launcher).")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}
