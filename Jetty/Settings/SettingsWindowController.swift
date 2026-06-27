import AppKit
import SwiftUI

/// Hosts the SwiftUI `SettingsView` in a standard titled window, presented on
/// demand (the agent has no SwiftUI `Settings` scene). Switches the app to
/// `.regular` while open so the window can take focus, and reverts to `.accessory`
/// on close. Mirrors Zap/MacDring. See PLAN.md §12.
final class SettingsWindowController: NSObject, NSWindowDelegate {

    private var window: NSWindow?
    private let preferences: Preferences
    private let store: DockStore
    private let systemDock: SystemDockController
    private let registry: DisplayRegistry
    private let updateChecker: UpdateChecker

    private weak var appToRestoreOnClose: NSRunningApplication?

    init(preferences: Preferences, store: DockStore, systemDock: SystemDockController,
         registry: DisplayRegistry, updateChecker: UpdateChecker) {
        self.preferences = preferences
        self.store = store
        self.systemDock = systemDock
        self.registry = registry
        self.updateChecker = updateChecker
    }

    func show() {
        if NSApp.activationPolicy() != .regular {
            let frontmost = NSWorkspace.shared.frontmostApplication
            appToRestoreOnClose = frontmost?.processIdentifier == NSRunningApplication.current.processIdentifier
                ? nil : frontmost
        }

        if window == nil {
            let root = SettingsView(preferences: preferences, store: store,
                                    systemDock: systemDock, registry: registry, updateChecker: updateChecker)
            let hosting = NSHostingController(rootView: root)
            hosting.sizingOptions = [.minSize]

            let window = NSWindow(contentViewController: hosting)
            window.title = "Jetty Settings"
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            window.setContentSize(NSSize(width: 560, height: 520))
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.center()
            window.setFrameAutosaveName("JettySettingsWindow")
            self.window = window
        }

        NSApp.setActivationPolicy(.regular)
        if #available(macOS 14.0, *) { NSApp.activate() } else { NSApp.activate(ignoringOtherApps: true) }
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        let restore = appToRestoreOnClose
        appToRestoreOnClose = nil
        NSApp.revertToAccessoryIfNoOrdinaryWindows(excluding: window)
        if let restore { AppLauncher.activate(restore) }
    }
}
