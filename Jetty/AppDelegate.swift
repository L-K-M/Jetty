import AppKit

/// Boots the app: wires the store, registry, running-apps model, dock controller,
/// and system-Dock manager; builds the menu-bar item; and starts the updater.
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {

    private let preferences = Preferences.shared
    private let store = DockStore()
    private let registry = DisplayRegistry()
    private let runningApps = RunningAppsModel()
    private let systemDock = SystemDockController()
    private lazy var controller = DockController(store: store, preferences: preferences,
                                                 registry: registry, runningApps: runningApps,
                                                 systemDock: systemDock)
    private let updateChecker = UpdateChecker(
        configuration: .init(owner: "L-K-M", repo: "Jetty", appName: "Jetty")
    )
    private lazy var settingsWindow = SettingsWindowController(
        preferences: preferences, store: store, systemDock: systemDock, updateChecker: updateChecker)

    private var statusItem: NSStatusItem?
    private var launchAtLoginItem: NSMenuItem?

    // MARK: NSApplicationDelegate

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard !Self.isRunningTests else { return }
        installMainMenu()
        setUpStatusItem()
        controller.start()
        updateChecker.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        guard !Self.isRunningTests else { return }
        store.flush()
        controller.teardown()
    }

    // MARK: Main menu

    /// Installs an App + Edit menu so the standard text-editing shortcuts reach the
    /// first responder (the Jetty Menu's search field, Settings text fields). Without
    /// it, an `LSUIElement` agent has no menu at all, so ⌘C/⌘V/etc. do nothing. The
    /// bar stays hidden while `.accessory`; only the key-equivalent routing matters.
    private func installMainMenu() {
        let mainMenu = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit Jetty", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        mainMenu.addItem(appItem)

        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: Selector(("cut:")), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: Selector(("copy:")), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: Selector(("paste:")), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: Selector(("selectAll:")), keyEquivalent: "a")
        editItem.submenu = editMenu
        mainMenu.addItem(editItem)

        NSApp.mainMenu = mainMenu
    }

    // MARK: Status item

    private func setUpStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = Self.statusBarImage()
        item.menu = buildMenu()
        statusItem = item
    }

    /// A template menu-bar glyph echoing the app: a rounded "dock" slab with three
    /// tile dots resting on it.
    static func statusBarImage() -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { _ in
            let slab = NSRect(x: 2, y: 4, width: 14, height: 7)
            let path = NSBezierPath(roundedRect: slab, xRadius: 3, yRadius: 3)
            NSColor.black.setStroke()
            path.lineWidth = 1.3
            path.stroke()
            for i in 0..<3 {
                let dot = NSRect(x: 4.5 + CGFloat(i) * 3.6, y: 6, width: 2.4, height: 2.4)
                NSColor.black.setFill()
                NSBezierPath(ovalIn: dot).fill()
            }
            return true
        }
        image.isTemplate = true
        return image
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self

        let toggle = NSMenuItem(title: "Toggle Dock", action: #selector(toggleDock), keyEquivalent: "")
        toggle.target = self
        menu.addItem(toggle)

        let jettyMenuItem = NSMenuItem(title: "Open Jetty Menu", action: #selector(openJettyMenu), keyEquivalent: "")
        jettyMenuItem.target = self
        menu.addItem(jettyMenuItem)

        menu.addItem(.separator())

        let settings = NSMenuItem(title: "Jetty Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)

        let updates = NSMenuItem(title: "Check for Updates…", action: #selector(checkForUpdates), keyEquivalent: "")
        updates.target = self
        menu.addItem(updates)

        let restore = NSMenuItem(title: "Restore System Dock", action: #selector(restoreSystemDock), keyEquivalent: "")
        restore.target = self
        menu.addItem(restore)

        menu.addItem(.separator())

        let login = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        login.target = self
        menu.addItem(login)
        launchAtLoginItem = login

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit Jetty", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
        return menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        preferences.refreshLaunchAtLoginStatus()
        launchAtLoginItem?.state = preferences.launchAtLogin ? .on : .off
    }

    // MARK: Actions

    @objc private func toggleDock() { controller.toggleAllDocks() }
    @objc private func openJettyMenu() { controller.openJettyMenu() }
    @objc private func openSettings() { settingsWindow.show() }
    @objc private func checkForUpdates() { updateChecker.checkNow() }

    @objc private func restoreSystemDock() {
        preferences.manageSystemDock = false
        systemDock.restoreSystemDock()
    }

    @objc private func toggleLaunchAtLogin() {
        preferences.launchAtLogin.toggle()
        launchAtLoginItem?.state = preferences.launchAtLogin ? .on : .off
    }

    @objc private func quit() { NSApp.terminate(nil) }

    // MARK: Helpers

    static var isRunningTests: Bool {
        NSClassFromString("XCTestCase") != nil ||
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }
}
