import AppKit
import Combine

/// The orchestrator: merges pinned + running apps into the shared `DockModel`,
/// resolves each target display's anchor into a `DockPanelController`, forwards
/// pointer moves for auto-hide/reveal, handles tile interactions, the optional
/// hotkeys, and managing (hiding/restoring) the system Dock. See PLAN.md §3.
final class DockController {

    private let store: DockStore
    private let preferences: Preferences
    private let registry: DisplayRegistry
    private let runningApps: RunningAppsModel
    private let systemDock: SystemDockController
    let model = DockModel()

    private let hoverMonitor = EdgeHoverMonitor()
    private var panels: [String: DockPanelController] = [:]
    private var cancellables = Set<AnyCancellable>()

    private let toggleHotkey = CarbonHotkey(identifier: 1)
    private let menuHotkey = CarbonHotkey(identifier: 2)

    /// The Jetty Menu launcher (created on first use).
    private lazy var jettyMenu = JettyMenuController(preferences: preferences)

    init(store: DockStore, preferences: Preferences, registry: DisplayRegistry,
         runningApps: RunningAppsModel, systemDock: SystemDockController) {
        self.store = store
        self.preferences = preferences
        self.registry = registry
        self.runningApps = runningApps
        self.systemDock = systemDock
    }

    // MARK: Lifecycle

    func start() {
        if !store.loadedFromDisk && store.items.isEmpty { seedDefaultItems() }
        ensureRunningSentinel()
        wireModelCallbacks()

        if preferences.manageSystemDock { systemDock.hideSystemDock() }

        rebuildModel()
        reconcilePanels()

        hoverMonitor.onMove = { [weak self] point in
            self?.panels.values.forEach { $0.handleMouseMoved(to: point) }
        }
        hoverMonitor.start()

        registerHotkeys()
        observe()
    }

    func teardown() {
        hoverMonitor.stop()
        panels.values.forEach { $0.close() }
        panels.removeAll()
        // Leave the system Dock as the user expects: restore it on quit if we hid it.
        if systemDock.isManaging { systemDock.restoreSystemDock() }
    }

    // MARK: Observation

    private func observe() {
        registry.onChange = { [weak self] in
            self?.systemDock.reassertIfManaging()
            self?.reconcilePanels()
        }

        runningApps.$apps
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.rebuildModel() }
            .store(in: &cancellables)

        store.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                DispatchQueue.main.async { self?.rebuildModel(); self?.relayoutPanels() }
            }
            .store(in: &cancellables)

        preferences.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                DispatchQueue.main.async { self?.applyPreferenceChange() }
            }
            .store(in: &cancellables)

        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.systemDock.reassertIfManaging()
        }
    }

    private func applyPreferenceChange() {
        // The system-Dock management toggle.
        if preferences.manageSystemDock {
            if !systemDock.isManaging { systemDock.hideSystemDock() }
        } else if systemDock.isManaging {
            systemDock.restoreSystemDock()
        }
        rebuildModel()
        reconcilePanels()
    }

    // MARK: Model

    private func rebuildModel() {
        model.rebuild(pinned: store.items, running: runningApps.apps,
                      showRunningApps: preferences.showRunningApps)
        relayoutPanels()
    }

    private func relayoutPanels() {
        panels.values.forEach { $0.layoutForCurrentState() }
    }

    // MARK: Panels

    private func targetUUIDs() -> [String] {
        switch preferences.displayScope {
        case .mainOnly: return [registry.mainScreenUUID()].compactMap { $0 }
        case .allDisplays: return registry.allUUIDs()
        }
    }

    private func effectiveAnchor(forUUID uuid: String) -> DockAnchor {
        var anchor = store.anchorOverride(forDisplayUUID: uuid) ?? preferences.defaultAnchor(forDisplayUUID: uuid)
        anchor.displayUUID = uuid
        return anchor
    }

    private func reconcilePanels() {
        let targets = Set(targetUUIDs())

        // Remove panels for displays no longer targeted/connected.
        for (uuid, panel) in panels where !targets.contains(uuid) {
            panel.close()
            panels[uuid] = nil
        }

        for uuid in targets {
            guard let screen = registry.screen(forUUID: uuid) else { continue }
            let anchor = effectiveAnchor(forUUID: uuid)
            if let panel = panels[uuid] {
                panel.update(screen: screen, anchor: anchor)
            } else {
                let panel = DockPanelController(displayUUID: uuid, screen: screen, anchor: anchor,
                                                model: model, preferences: preferences)
                panels[uuid] = panel
                panel.showInitial()
            }
        }
    }

    // MARK: Interactions

    private func wireModelCallbacks() {
        model.onOpenTile = { [weak self] tile in self?.open(tile) }
        model.onDropFiles = { [weak self] tile, urls in self?.handleDrop(urls, on: tile) }
        model.onRequestContextActions = { [weak self] tile in self?.contextActions(for: tile) ?? [] }
        model.onReorder = { [weak self] orderedIDs in self?.reorder(to: orderedIDs) }
    }

    /// Applies a drag-to-reorder: `orderedIDs` is the new order of the reorderable
    /// slots' backing items. Non-reorderable items (e.g. a hidden running-apps
    /// sentinel when running apps are off) keep their positions.
    private func reorder(to orderedIDs: [UUID]) {
        var items = store.items
        let idSet = Set(orderedIDs)
        let byID = Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let movablePositions = items.indices.filter { idSet.contains(items[$0].id) }
        let newMovable = orderedIDs.compactMap { byID[$0] }
        guard newMovable.count == movablePositions.count else { return }
        for (position, item) in zip(movablePositions, newMovable) { items[position] = item }
        store.setItems(items)
    }

    private func open(_ tile: DockTile) {
        switch tile.kind {
        case .application:
            openApplication(tile)
        case .file, .folder, .url:
            if let url = tile.url { NSWorkspace.shared.open(url) }
        case .trash:
            AppLauncher.openTrash()
        case .clock:
            openCalendar()
        case .jettyMenu:
            openJettyMenu()
            return   // don't hide the dock; the menu is its own panel
        case .separator, .runningApps:
            return
        }
        hideRevealedDocks()
    }

    private func openApplication(_ tile: DockTile) {
        let appURL = tile.url ?? tile.bundleIdentifier.flatMap { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) }
        if let appURL {
            let name = tile.displayName.isEmpty ? appURL.deletingPathExtension().lastPathComponent : tile.displayName
            RecentAppsStore.shared.record(name: name, bundleID: tile.bundleIdentifier, url: appURL)
        }
        if let bundleID = tile.bundleIdentifier,
           let running = runningApps.runningApplication(bundleIdentifier: bundleID) {
            AppLauncher.activate(running)
        } else if let appURL {
            AppLauncher.launchApplication(at: appURL)
        }
    }

    private func handleDrop(_ urls: [URL], on tile: DockTile) {
        switch tile.kind {
        case .application:
            if let appURL = tile.url ?? tile.bundleIdentifier.flatMap({ NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) }) {
                AppLauncher.open(urls, withApplicationAt: appURL)
            }
        case .trash:
            AppLauncher.moveToTrash(urls)
        default:
            // Dropped on a non-app tile → pin the files to the dock, skipping any
            // already-pinned URL so a repeat drop doesn't create duplicate tiles.
            for url in urls where !isAlreadyPinned(url) {
                store.addItem(makePinnedItem(for: url))
            }
        }
    }

    private func makePinnedItem(for url: URL) -> DockItem {
        var item = DockItem.fromFileURL(url)
        item.bookmark = BookmarkResolver.bookmark(for: url)
        return item
    }

    /// Whether a file/folder URL is already pinned (compared by standardized path).
    private func isAlreadyPinned(_ url: URL) -> Bool {
        let target = url.standardizedFileURL
        return store.items.contains { $0.url?.standardizedFileURL == target }
    }

    // MARK: Context menu

    private func contextActions(for tile: DockTile) -> [DockContextAction] {
        var actions: [DockContextAction] = []
        switch tile.kind {
        case .application:
            let bundleID = tile.bundleIdentifier
            let running = bundleID.flatMap { runningApps.runningApplication(bundleIdentifier: $0) }
            if let running {
                actions.append(DockContextAction(title: "Show") { AppLauncher.activate(running) })
                actions.append(DockContextAction(title: running.isHidden ? "Unhide" : "Hide") {
                    if running.isHidden { running.unhide() } else { running.hide() }
                })
                actions.append(DockContextAction(title: "Quit", isDestructive: true) { AppLauncher.quit(running) })
                actions.append(.separator)
            } else {
                actions.append(DockContextAction(title: "Open") { [weak self] in self?.openApplication(tile) })
            }
            if let itemID = tile.itemID {
                actions.append(DockContextAction(title: "Remove from Dock", isDestructive: true) { [weak self] in
                    self?.store.removeItem(id: itemID)
                })
            } else {
                actions.append(DockContextAction(title: "Keep in Dock") { [weak self] in self?.pin(tile) })
            }
            if let appURL = tile.url ?? bundleID.flatMap({ NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) }) {
                actions.append(DockContextAction(title: "Show in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([appURL])
                })
            }
        case .file, .folder, .url:
            actions.append(DockContextAction(title: "Open") { [weak self] in self?.open(tile) })
            if let url = tile.url, url.isFileURL {
                actions.append(DockContextAction(title: "Show in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                })
            }
            if let itemID = tile.itemID {
                actions.append(.separator)
                actions.append(DockContextAction(title: "Remove from Dock", isDestructive: true) { [weak self] in
                    self?.store.removeItem(id: itemID)
                })
            }
        case .trash:
            actions.append(DockContextAction(title: "Open Trash") { AppLauncher.openTrash() })
            actions.append(DockContextAction(title: "Empty Trash…", isDestructive: true) {
                PowerCommandRunner.run(.emptyTrash)
            })
        case .clock:
            actions.append(DockContextAction(title: "Open Calendar") { [weak self] in self?.openCalendar() })
        case .jettyMenu:
            actions.append(DockContextAction(title: "Open Jetty Menu") { [weak self] in self?.openJettyMenu() })
        case .separator, .runningApps:
            break
        }
        return actions
    }

    private func pin(_ tile: DockTile) {
        guard tile.kind == .application else { return }
        let url = tile.url ?? tile.bundleIdentifier.flatMap { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) }
        guard let url else { return }
        // Don't double-pin an app that's already in the dock.
        if let bundleID = tile.bundleIdentifier, store.contains(bundleIdentifier: bundleID) { return }
        // Capture a bookmark (like ItemsView / drag-to-pin do) so the pin tracks the
        // app being moved or renamed, not just its current path.
        var item = DockItem.application(at: url, name: tile.displayName, bundleIdentifier: tile.bundleIdentifier)
        item.bookmark = BookmarkResolver.bookmark(for: url)
        store.addItem(item)
    }

    // MARK: Hotkeys / menu

    private func registerHotkeys() {
        let mods = KeyCode.Modifier.control | KeyCode.Modifier.option | KeyCode.Modifier.command
        toggleHotkey.onPressed = { [weak self] in self?.toggleAllDocks() }
        toggleHotkey.register(keyCode: KeyCode.d, modifiers: mods)
        menuHotkey.onPressed = { [weak self] in self?.openJettyMenu() }
        menuHotkey.register(keyCode: KeyCode.space, modifiers: mods)
    }

    func toggleAllDocks() { panels.values.forEach { $0.toggle() } }

    private func hideRevealedDocks() {
        guard preferences.autoHide else { return }
        panels.values.forEach { $0.hide() }
    }

    func openJettyMenu() {
        let screen = NSScreen.main ?? NSScreen.screens.first
        jettyMenu.toggle(on: screen)
    }

    private func openCalendar() {
        // Try known Calendar bundle ids, then the on-disk app, so a clock-tile click
        // never silently no-ops if Calendar was replaced/renamed (BUG-6).
        for bundleID in ["com.apple.iCal", "com.apple.Calendar"] {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
                AppLauncher.launchApplication(at: url); return
            }
        }
        let path = "/System/Applications/Calendar.app"
        if FileManager.default.fileExists(atPath: path) {
            AppLauncher.launchApplication(at: URL(fileURLWithPath: path))
        }
    }

    // MARK: First-run seed

    private func seedDefaultItems() {
        var items: [DockItem] = []
        let bundleIDs = ["com.apple.finder", "com.apple.Safari", "com.apple.mail", "com.apple.systempreferences"]
        for bundleID in bundleIDs {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
                items.append(DockItem.application(at: url, bundleIdentifier: bundleID))
            }
        }
        items.append(DockItem(kind: .separator))
        items.append(DockItem(kind: .runningApps, displayName: "Running Apps"))
        items.append(DockItem(kind: .separator))
        items.append(DockItem(kind: .clock, displayName: "Clock"))
        items.append(DockItem(kind: .jettyMenu, displayName: "Jetty Menu"))
        items.append(DockItem(kind: .trash, displayName: "Trash"))
        store.setItems(items)
    }

    /// Ensures a `.runningApps` sentinel exists so the running-apps cluster is a
    /// reorderable unit. Migrates docs created before the sentinel (its absence made
    /// running apps a non-movable trailing block). Inserts it before the Trash if one
    /// is present, else at the end. No-op once present.
    private func ensureRunningSentinel() {
        guard !store.items.contains(where: { $0.kind == .runningApps }) else { return }
        var items = store.items
        let sentinel = DockItem(kind: .runningApps, displayName: "Running Apps")
        if let trashIndex = items.firstIndex(where: { $0.kind == .trash }) {
            items.insert(sentinel, at: trashIndex)
        } else {
            items.append(sentinel)
        }
        store.setItems(items)
    }
}
