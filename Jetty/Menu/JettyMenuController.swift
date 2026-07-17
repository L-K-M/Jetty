import AppKit
import SwiftUI

/// A borderless panel that can still become key, so the Jetty Menu's search field
/// receives keystrokes.
private final class KeyableMenuPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

extension Notification.Name {
    /// Posted by `JettyMenuController.show` after the panel becomes key, so the
    /// search field re-asserts focus on every open (the reused hosting view's
    /// `.onAppear` doesn't reliably refire).
    static let jettyMenuDidShow = Notification.Name("JettyMenuDidShowNotification")
}

/// Presents the Jetty Menu launcher: builds the key panel, positions it (centered
/// for the hotkey / status-item paths, or anchored to the Jetty tile like a pop-up
/// menu when opened from the dock), briefly activates Jetty so the search field is
/// focused, and installs a local key monitor for ↑/↓/Return/Esc (so it works on
/// macOS 13+, where SwiftUI `onKeyPress` isn't available). Closing returns
/// activation to the previously-frontmost app. See PLAN.md §8.2.
final class JettyMenuController {

    /// Where a dock-tile-initiated open should anchor the panel: the tile's
    /// screen-space center, the dock strip it sits in, and the dock's edge.
    struct TileAnchor {
        let point: CGPoint
        let dockFrame: CGRect
        let edge: DockEdge
    }

    private let preferences: Preferences
    private let appIndex = AppIndex()
    private lazy var model = JettyMenuModel(appIndex: appIndex)

    private var panel: KeyableMenuPanel?
    private var keyMonitor: Any?
    private var resignObserver: Any?
    private weak var appToRestoreOnClose: NSRunningApplication?
    /// Whether `show()` captured an app to restore. Distinguishes "the captured app
    /// quit while the menu was open" (restore is nil/terminated but this is true →
    /// fall back to Finder) from the deliberate nil cases — Jetty was already
    /// frontmost, or a launched app is taking focus (F-M3) — where close() must not
    /// activate anything (M19).
    private var hadRestoreTarget = false
    private(set) var isOpen = false

    init(preferences: Preferences) {
        self.preferences = preferences
    }

    func toggle(on screen: NSScreen?, from anchor: TileAnchor? = nil) {
        // Spotlight/Raycast behavior: re-invoking the hotkey while the menu is open
        // on *another* display moves it to the active screen rather than dismissing.
        if isOpen, let panel, let target = screen ?? NSScreen.main, panel.screen !== target {
            positionPanel(panel, on: target, anchor: nil)
            panel.makeKeyAndOrderFront(nil)
            return
        }
        if isOpen { close() } else { show(on: screen, from: anchor) }
    }

    func show(on screen: NSScreen?, from anchor: TileAnchor? = nil) {
        guard !isOpen else { return }
        let frontmost = NSWorkspace.shared.frontmostApplication
        appToRestoreOnClose = frontmost?.processIdentifier == NSRunningApplication.current.processIdentifier ? nil : frontmost
        hadRestoreTarget = appToRestoreOnClose != nil

        model.reset()
        model.recentsProvider = { RecentAppsStore.shared.recentItems() }
        model.snapshotRecents()   // read UserDefaults once per show, not per keystroke
        model.onLaunch = { [weak self] item in
            RecentAppsStore.shared.record(name: item.name, bundleID: item.bundleID, url: item.url)
            // The launched app is being given focus (config.activates) — don't let close()
            // restore the previously-frontmost app over it (F-M3).
            self?.appToRestoreOnClose = nil
            self?.hadRestoreTarget = false
            AppLauncher.launchApplication(at: item.url)
            self?.close()
        }
        model.onRunPower = { [weak self] command in self?.runPower(command) }
        model.onClose = { [weak self] in self?.close() }
        model.onWebSearch = { [weak self] query in self?.webSearch(query) }
        model.onRunCommand = { [weak self] command in self?.runCommand(command) }
        model.onCopyValue = { [weak self] value in
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(value, forType: .string)
            self?.close()
        }
        appIndex.reload()   // pick up newly installed/removed apps each open (ISSUE-6)

        let panel = self.panel ?? makePanel()
        self.panel = panel
        positionPanel(panel, on: screen ?? NSScreen.main, anchor: anchor)

        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        // The hosting view is reused across opens and `.onAppear` doesn't reliably
        // refire — tell the search field to re-assert focus on every show.
        NotificationCenter.default.post(name: .jettyMenuDidShow, object: nil)
        installKeyMonitor()
        installResignObserver(for: panel)
        isOpen = true
    }

    func close() {
        guard isOpen else { return }
        isOpen = false
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor); self.keyMonitor = nil }
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver); self.resignObserver = nil }
        panel?.orderOut(nil)
        // Hand activation back only if Jetty is still the active app — i.e. the menu was
        // dismissed by Esc / copy / a command. If the user dismissed it by clicking
        // another app, that app is already frontmost and must not be yanked away (F-M3).
        if NSApp.isActive {
            if let restore = appToRestoreOnClose, !restore.isTerminated {
                AppLauncher.activate(restore)
            } else if hadRestoreTarget {
                // The captured frontmost app quit while the menu was open. With nothing
                // to hand focus back to, Jetty — an LSUIElement with no menu bar — would
                // be left "frontmost"; fall back to activating Finder (M19).
                if let finder = NSRunningApplication
                    .runningApplications(withBundleIdentifier: "com.apple.finder").first {
                    AppLauncher.activate(finder)
                }
            }
        }
        appToRestoreOnClose = nil
        hadRestoreTarget = false
    }

    // MARK: Build

    private func makePanel() -> KeyableMenuPanel {
        let hosting = NSHostingController(rootView: JettyMenuView(model: model, preferences: preferences))
        let panel = KeyableMenuPanel(contentViewController: hosting)
        panel.styleMask = [.borderless, .nonactivatingPanel]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .popUpMenu
        panel.isReleasedWhenClosed = false
        panel.isMovableByWindowBackground = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.setContentSize(NSSize(width: 420, height: 460))
        return panel
    }

    private func positionPanel(_ panel: NSPanel, on screen: NSScreen?, anchor: TileAnchor?) {
        guard let screen = screen ?? NSScreen.main else { return }
        let size = panel.frame.size
        let vf = screen.visibleFrame
        // A dock-tile click anchors the menu to the clicked tile like a pop-up menu;
        // the hotkey / status-item paths keep the Spotlight-style centered position.
        let origin: NSPoint
        if let anchor {
            origin = DockContextMenuPlacement.panelOrigin(
                panelSize: size, sourcePoint: anchor.point, dockFrame: anchor.dockFrame,
                visibleFrame: vf, edge: anchor.edge)
        } else {
            origin = NSPoint(x: vf.midX - size.width / 2, y: vf.midY - size.height / 2)
        }
        panel.setFrameOrigin(origin)
    }

    private func runPower(_ command: PowerCommand) {
        if command.isDestructive {
            let alert = NSAlert()
            alert.messageText = "\(command.title)?"
            alert.informativeText = command.confirmationPrompt
            alert.addButton(withTitle: command.title)
            alert.addButton(withTitle: "Cancel")
            NSApp.activate(ignoringOtherApps: true)
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }
        close()
        PowerCommandRunner.run(command)
    }

    /// Opens a default-browser web search for `query`, then closes the menu (ND-9).
    private func webSearch(_ query: String) {
        var components = URLComponents(string: "https://www.google.com/search")
        components?.queryItems = [URLQueryItem(name: "q", value: query)]
        // URLComponents leaves '+' literal (it's a valid query character), but Google
        // decodes '+' in a query as a space — so "c++" would search for "c  ". Percent-
        // encode it so plus signs survive (F-L3). Read into a local first: mutating
        // `percentEncodedQuery` while also reading it in the same statement is an
        // overlapping access to the `components` value and won't compile.
        if let encoded = components?.percentEncodedQuery {
            components?.percentEncodedQuery = encoded.replacingOccurrences(of: "+", with: "%2B")
        }
        if let url = components?.url {
            NSWorkspace.shared.open(url)
        }
        close()
    }

    /// Runs a quick-toggle command, then closes the menu (ND-9).
    private func runCommand(_ command: MenuCommand) {
        close()
        MenuCommand.run(command)
    }

    /// Dismisses the menu when it stops being the key window — i.e. the user
    /// clicked another app, ⌘-Tabbed away, or otherwise moved focus — matching how
    /// Spotlight/Alfred/Raycast behave. Guards against the confirmation alert for a
    /// destructive power command (which is itself modal) self-dismissing the menu.
    private func installResignObserver(for panel: NSPanel) {
        resignObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification, object: panel, queue: .main
        ) { [weak self] _ in
            guard NSApp.modalWindow == nil else { return }
            self?.close()
        }
    }

    // MARK: Keyboard

    private func installKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, let panel = self.panel else { return event }
            // Only act when the menu panel is key — the local monitor is app-global, so a
            // focused Settings window or a modal alert must keep its own Esc/Return/arrows
            // (M15).
            guard panel.isKeyWindow else { return event }
            // While an IME is composing (marked text in the field editor), let Return/Esc/
            // arrows drive the candidate window instead of the menu — otherwise CJK input
            // is unusable (F-M2).
            if let editor = panel.firstResponder as? NSTextView, editor.hasMarkedText() { return event }
            switch event.keyCode {
            case 126: self.model.moveSelection(-1); return nil   // up
            case 125: self.model.moveSelection(1); return nil    // down
            case 36, 76: self.model.activateSelection(); return nil  // return / enter
            case 53:                                             // escape
                // First Esc clears a non-empty query (and resets the selection via the
                // query's didSet); a second Esc closes — Spotlight behavior (FAB-D16).
                if self.model.query.isEmpty { self.close() } else { self.model.reset() }
                return nil
            default: return event                                 // let typing reach the field
            }
        }
    }
}
