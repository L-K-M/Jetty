import SwiftUI
import AppKit
import CoreGraphics

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
                Toggle("Show window previews when hovering an app", isOn: $preferences.windowPreviews)
                Text("Hovering a running app's tile shows its open windows. Click a preview to raise it, or use the corner button to minimize.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Accessibility — for click-to-raise / minimize") {
                statusRow(granted: accessibilityTrusted)
                Text("Lets Jetty raise and minimize a specific window from its preview. Without it, clicking a preview just brings the app forward.")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button("Request…") { AccessibilityAuthorizer.prompt(); refresh() }
                    Button("Open Settings") { AccessibilityAuthorizer.openSystemSettings() }
                }
            }

            Section("Screen Recording — for live preview thumbnails") {
                statusRow(granted: screenRecordingGranted)
                Text("Lets the previews show live window thumbnails. Optional — without it you still get the window list and raise/minimize.")
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
