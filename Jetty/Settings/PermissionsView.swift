import SwiftUI
import AppKit
import CoreGraphics
import Combine

/// Reports the optional permissions used by Jetty's *later* power features. The core
/// dock needs none of these — this pane exists so the window-peeking / live-preview
/// milestones have a home and users understand the trade-offs. See PLAN.md §12.
struct PermissionsView: View {
    @ObservedObject var preferences: Preferences
    @State private var accessibilityTrusted = AccessibilityAuthorizer.isTrusted
    @State private var screenRecordingGranted = CGPreflightScreenCaptureAccess()

    var body: some View {
        Form {
            Section("Core dock") {
                Label("The dock, launching, indicators, positioning, the clock, and the Jetty Menu need no permissions.",
                      systemImage: "checkmark.seal")
                    .foregroundStyle(.green)
            }

            Section("Window previews") {
                Picker("Hovering an app's tile shows", selection: $preferences.windowPreviewMode) {
                    ForEach(WindowPreviewMode.allCases) { Text($0.label).tag($0) }
                }
                Text(modeExplanation)
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Accessibility — for window names & click-to-raise / minimize") {
                statusRow(granted: accessibilityTrusted)
                Text("Lets Jetty read window titles and raise/minimize a specific window. Without it, names mode shows generic labels and clicking just brings the app forward. Needed by both modes for precise control — but neither mode *requires* it.")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button("Request…") { AccessibilityAuthorizer.prompt(); refresh() }
                    Button("Open Settings") { AccessibilityAuthorizer.openSystemSettings() }
                }
            }

            Section("Screen Recording — only for “Live thumbnails”") {
                statusRow(granted: screenRecordingGranted)
                Text("Required only by the “Live thumbnails” preview mode. The default “Window names” mode never uses it.")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button("Request…") { CGRequestScreenCaptureAccess(); refresh() }
                    Button("Open Settings") { openScreenRecordingSettings() }
                }
            }

            Section {
                Button("Refresh") { refresh() }
            }
        }
        .formStyle(.grouped)
        .onAppear(perform: refresh)
        // Poll so granting a permission in System Settings reflects here without a
        // manual refresh or reopening the tab.
        .onReceive(Timer.publish(every: 2, on: .main, in: .common).autoconnect()) { _ in refresh() }
    }

    private var modeExplanation: String {
        switch preferences.windowPreviewMode {
        case .off: return "No preview appears when you hover an app."
        case .names: return "Shows a list of the app's window names — needs no Screen Recording. Click a name to raise that window (with Accessibility) or to bring the app forward."
        case .thumbnails: return "Shows live thumbnails of the app's windows — needs Screen Recording. Click a thumbnail to raise it, or the corner button to minimize."
        }
    }

    private func statusRow(granted: Bool) -> some View {
        Label(granted ? "Granted" : "Not granted",
              systemImage: granted ? "checkmark.circle.fill" : "xmark.circle")
            .foregroundStyle(granted ? .green : .secondary)
    }

    private func refresh() {
        accessibilityTrusted = AccessibilityAuthorizer.isTrusted
        screenRecordingGranted = CGPreflightScreenCaptureAccess()
    }

    private func openScreenRecordingSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }
}
