import SwiftUI
import AppKit
import CoreGraphics

/// Reports the optional permissions used by Jetty's *later* power features. The core
/// dock needs none of these — this pane exists so the window-peeking / live-preview
/// milestones have a home and users understand the trade-offs. See PLAN.md §12.
struct PermissionsView: View {
    @State private var accessibilityTrusted = AccessibilityAuthorizer.isTrusted
    @State private var screenRecordingGranted = CGPreflightScreenCaptureAccess()

    var body: some View {
        Form {
            Section("Core dock") {
                Label("The dock, launching, indicators, positioning, the clock, and the Jetty Menu need no permissions.",
                      systemImage: "checkmark.seal")
                    .foregroundStyle(.green)
            }

            Section("Accessibility — for window management (coming soon)") {
                statusRow(granted: accessibilityTrusted)
                Text("Lets Jetty list an app's windows and click-to-raise / minimize them.")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button("Request…") { AccessibilityAuthorizer.prompt(); refresh() }
                    Button("Open Settings") { AccessibilityAuthorizer.openSystemSettings() }
                }
            }

            Section("Screen Recording — for live window previews (coming soon)") {
                statusRow(granted: screenRecordingGranted)
                Text("Lets Jetty show a live thumbnail when you hover an app's tile. Optional — the dock works fully without it.")
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
