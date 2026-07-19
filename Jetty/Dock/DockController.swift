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
    private let trashMonitor = TrashMonitor()
    private let responsivenessMonitor = AppResponsivenessMonitor()
    private var panels: [String: DockPanelController] = [:]
    private var cancellables = Set<AnyCancellable>()

    private let toggleHotkey = CarbonHotkey(identifier: 1)
    private let menuHotkey = CarbonHotkey(identifier: 2)

    /// Token for the block-based wake observer, so `teardown()` can remove it (otherwise
    /// every start/teardown cycle stacks another live observer) — H24.
    private var wakeObserver: NSObjectProtocol?
    private var trashVolumeObservers: [NSObjectProtocol] = []
    private var trashWork: DispatchWorkItem?

    /// Last-seen "structural" preference signatures, so a preference mutation only
    /// does the work it actually needs: pure-appearance tweaks (opacity/tint/corner/
    /// magnification-magnitude…) flow to the views via `@ObservedObject` and touch no
    /// panels; only geometry/anchor/tile-set changes rebuild or reconcile (BUG-7).
    private var prefSig: (reconcile: String, model: String, layout: String, hotkeys: String)?

    /// The Jetty Menu launcher (created on first use).
    private lazy var jettyMenu = JettyMenuController(preferences: preferences)
    /// The folder-stack popover (MF-2).
    private lazy var folderStack = FolderStackController(preferences: preferences)
    /// The hover window-peek popover (live previews + raise/minimize).
    private lazy var windowPeek = WindowPeekController(preferences: preferences)
    private var peekWork: DispatchWorkItem?

    init(store: DockStore, preferences: Preferences, registry: DisplayRegistry,
         runningApps: RunningAppsModel, systemDock: SystemDockController) {
        self.store = store
        self.preferences = preferences
        self.registry = registry
        self.runningApps = runningApps
        self.systemDock = systemDock
    }

    // MARK: Lifecycle

    /// True once `start()` ran, so `teardown()` on a never-started controller is a
    /// no-op — a terminating duplicate instance must not restore the system Dock or
    /// touch the shared `isManaging` state on its way out (FAB-B1).
    private var started = false

    func start() {
        started = true
        if !store.loadedFromDisk && store.items.isEmpty { seedDefaultItems() }
        ensureRunningSentinel()
        wireModelCallbacks()

        if preferences.manageSystemDock { systemDock.hideSystemDock() }

        configureTrashMonitoring()
        configureResponsivenessMonitoring()
        observe()   // install volume/wake observers before the initial Trash arm/scan
        rebuildModel()
        reconcilePanels()
        prefSig = preferenceSignatures()
        refreshTrashState()   // initial resolution; the watcher keeps it live

        hoverMonitor.onMove = { [weak self] point in
            self?.panels.values.forEach { $0.handleMouseMoved(to: point) }
        }
        hoverMonitor.start()

        registerHotkeys()
    }

    func teardown() {
        guard started else { return }
        started = false
        hoverMonitor.stop()
        trashWork?.cancel(); trashWork = nil
        trashMonitor.stop()
        responsivenessMonitor.stop()
        model.setUnresponsivePIDs([])
        LiveSystemStats.shared.setRunning(false)
        peekWork?.cancel(); peekWork = nil
        windowPeek.hide()
        folderStack.close()
        panels.values.forEach { $0.close() }
        panels.removeAll()
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
            self.wakeObserver = nil
        }
        trashVolumeObservers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        trashVolumeObservers.removeAll()
        cancellables.removeAll()
        registry.onChange = nil
        trashMonitor.onChange = nil
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
            .sink { [weak self] apps in
                self?.responsivenessMonitor.setApplications(apps)
                self?.rebuildModel()
            }
            .store(in: &cancellables)

        store.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                DispatchQueue.main.async { self?.rebuildModel(); self?.reconcilePanels() }
            }
            .store(in: &cancellables)

        preferences.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                DispatchQueue.main.async { self?.applyPreferenceChange() }
            }
            .store(in: &cancellables)

        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.systemDock.reassertIfManaging()
            self?.responsivenessMonitor.resetAfterWake()
            self?.refreshTrashMonitoring()
        }

        for name in [NSWorkspace.didMountNotification,
                     NSWorkspace.didUnmountNotification,
                     NSWorkspace.didRenameVolumeNotification] {
            let observer = NSWorkspace.shared.notificationCenter.addObserver(
                forName: name, object: nil, queue: .main) { [weak self] _ in
                    self?.refreshTrashMonitoring()
                }
            trashVolumeObservers.append(observer)
        }
    }

    private func applyPreferenceChange() {
        // The system-Dock management toggle (cheap, always checked).
        if preferences.manageSystemDock {
            if !systemDock.isManaging { systemDock.hideSystemDock() }
        } else if systemDock.isManaging {
            systemDock.restoreSystemDock()
        }

        // Only do the expensive work the change actually requires (BUG-7). Each tile
        // already observes `preferences` directly, so pure-appearance edits repaint
        // without recreating anchors or panels.
        let sig = preferenceSignatures()
        defer { prefSig = sig }
        guard let previous = prefSig else { return }   // start() seeded the baseline

        if sig.model != previous.model { rebuildModel() }                 // tile set
        if sig.reconcile != previous.reconcile { reconcilePanels() }      // panel set / anchors
        else if sig.model == previous.model && sig.layout != previous.layout {
            relayoutPanels()                                              // frame size only
        }
        if sig.hotkeys != previous.hotkeys { registerHotkeys() }          // shortcut bindings

        // Auto-hide is OFF: make sure every panel is actually revealed. A panel's
        // reveal state is only seeded at creation, so turning auto-hide off while a
        // dock was hidden re-applied the hidden (click-through) transform forever —
        // edge hover is gated on `autoHide`, and nothing else calls `reveal()`.
        // `reveal()` no-ops when already revealed, so this is idempotent.
        if !preferences.autoHide {
            panels.values.forEach { $0.reveal(animated: false) }
        }
    }

    /// The subset of preferences that change the dock's structure, split by the work
    /// each tier needs: `reconcile` (which panels exist + their anchors), `model`
    /// (the merged tile set), `layout` (panel frame size), and `hotkeys` (the global
    /// shortcut bindings). Anything not here is pure appearance and needs no work.
    private func preferenceSignatures() -> (reconcile: String, model: String, layout: String, hotkeys: String) {
        let p = preferences
        return (
            reconcile: [p.edge.rawValue, p.alignment.rawValue, String(p.offset),
                        String(p.inset)].joined(separator: "|"),
            model: [String(p.showRunningApps), p.trashIconStyle.rawValue].joined(separator: "|"),
            layout: [String(p.iconSize), String(p.tileSpacing), String(p.magnificationEnabled),
                     String(p.magnification), String(p.autoHide), p.revealTrigger.rawValue,
                     // The face style/zoom change the panel's clock headroom
                     // (DockPanelController.contentSize), so they must relayout.
                     p.clockFace.rawValue, String(p.clockFaceZoom)].joined(separator: "|"),
            hotkeys: p.toggleHotkey.jsonString + "·" + p.menuHotkey.jsonString
        )
    }

    // MARK: Model

    private func rebuildModel() {
        guard started else { return }
        updateTrashMonitoring()
        model.setTrashIconStyle(preferences.trashIconStyle)
        model.rebuild(pinned: store.items, running: runningApps.apps,
                      showRunningApps: preferences.showRunningApps)
        relayoutPanels()
        updateLiveStats()
    }

    private func configureTrashMonitoring() {
        trashMonitor.onChange = { [weak self] in
            guard let self else { return }
            self.trashWork?.cancel()
            let work = DispatchWorkItem { [weak self] in
                guard let self, self.hasTrashItem else { return }
                self.trashWork = nil
                self.refreshTrashState()
            }
            self.trashWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
        }
    }

    // MARK: Trash fullness resolution (see TRASH.md)

    /// The state the model currently renders — kept here so we only rebuild when the
    /// *resolved* state actually flips, not on every resolution pass.
    private var resolvedTrashState: DockModel.TrashState = .unknown
    private var trashResolveInFlight = false
    /// Last resolution start — reveal-triggered resolutions are throttled so a
    /// fidgety pointer can't spam Finder with AppleEvents.
    private var lastTrashResolve: Date = .distantPast

    /// Resolves the Trash's fullness through the tiered pipeline (probe → Finder
    /// Automation → honest default), off the main thread, and republishes the model
    /// only when the state actually changes. Cheap to call liberally: coalesced by
    /// an in-flight flag and (for reveal-driven calls) a short throttle.
    func refreshTrashState(throttle: Bool = false) {
        guard started, hasTrashItem, !trashResolveInFlight else { return }
        if throttle, Date().timeIntervalSince(lastTrashResolve) < 5 { return }
        trashResolveInFlight = true
        lastTrashResolve = Date()
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let probe = DockModel.probeTrashFullness()
            let automation = FinderAutomation.permissionStatus()
            DispatchQueue.main.async { [weak self] in
                guard let self, self.started else { return }
                self.trashResolveInFlight = false
                switch TrashStateResolver.plan(probe: probe,
                                               finderAutomationGranted: automation == .granted) {
                case .useProbe(let state):
                    self.applyResolvedTrashState(state)
                case .askFinder:
                    self.queryFinderTrashCount()
                case .indeterminate:
                    self.applyResolvedTrashState(.unknown)
                }
            }
        }
    }

    private func queryFinderTrashCount() {
        FinderAutomation.trashItemCount { [weak self] count in
            guard let self, self.started else { return }
            self.applyResolvedTrashState(count.map { $0 > 0 ? .full : .empty } ?? .unknown)
        }
    }

    private func applyResolvedTrashState(_ state: DockModel.TrashState) {
        guard state != resolvedTrashState, started, hasTrashItem else { return }
        resolvedTrashState = state
        model.setTrashState(state)
        rebuildModel()
    }

    private func configureResponsivenessMonitoring() {
        responsivenessMonitor.onChange = { [weak self] pids in
            guard let self, self.started else { return }
            self.model.setUnresponsivePIDs(pids)
        }
        responsivenessMonitor.setApplications(runningApps.apps)
        responsivenessMonitor.start()
    }

    private var hasTrashItem: Bool {
        store.items.contains(where: Self.isTrashItem)
    }

    private func updateTrashMonitoring() {
        if started && hasTrashItem {
            trashMonitor.start()
        } else {
            trashWork?.cancel(); trashWork = nil
            trashMonitor.stop()
        }
    }

    private func refreshTrashMonitoring() {
        guard started, hasTrashItem else { return }
        trashMonitor.refresh()
        refreshTrashState()
    }

    /// Runs the shared system sampler only while a panel actually shows a CPU/battery
    /// widget — authoritative state, so the timer can't leak if SwiftUI skips an
    /// ordered-out panel's `onDisappear` (ISSUE-5).
    private func updateLiveStats() {
        let hasWidget = model.tiles.contains { $0.kind == .systemMonitor || $0.kind == .battery }
        LiveSystemStats.shared.setRunning(hasWidget && !panels.isEmpty)
    }

    private func relayoutPanels() {
        panels.values.forEach { $0.layoutForCurrentState() }
    }

    // MARK: Panels

    private func targetUUIDs() -> [String] {
        // Every connected display gets a dock, minus the ones the user turned off in
        // Displays — but never leave *every* display dockless. If disabling would remove
        // all docks (they turned them all off, or the only screen left is a disabled one),
        // the opt-outs are ignored so a dock always exists somewhere.
        return Self.enabledTargets(base: registry.allUUIDs(), disabled: store.document.disabledDisplayUUIDs)
    }

    /// `base` displays minus the user's opt-outs — but never empty: if every target is
    /// disabled, all of `base` is returned so a dock always exists somewhere. Pure, so
    /// the "never left without a dock" guarantee is unit-tested.
    static func enabledTargets(base: [String], disabled: Set<String>) -> [String] {
        let enabled = base.filter { !disabled.contains($0) }
        return enabled.isEmpty ? base : enabled
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
                panel.onDropToPin = { [weak self] urls in self?.pinDroppedURLs(urls) }
                // The Trash can must never be staler than the user's last look at
                // the dock (throttled inside) — TRASH.md.
                panel.onReveal = { [weak self] in self?.refreshTrashState(throttle: true) }
                panels[uuid] = panel
                panel.showInitial()
                // The pointer may already be resting in the new panel's reveal zone
                // (hot-plug, or a settings change that recreated panels): the edge
                // monitor only fires on *movement*, so seed the current position or
                // the dock would stay hidden until the pointer twitches.
                panel.handleMouseMoved(to: NSEvent.mouseLocation)
            }
        }
        updateLiveStats()
    }

    // MARK: Interactions

    private func wireModelCallbacks() {
        model.onOpenTile = { [weak self] tile in self?.open(tile) }
        model.onDropFiles = { [weak self] tile, urls in self?.handleDrop(urls, on: tile) }
        model.onRequestContextActions = { [weak self] tile in self?.contextActions(for: tile) ?? [] }
        model.onContextMenuPresentationChanged = { [weak self] displayUUID, presented in
            guard let self else { return }
            self.panels[displayUUID]?.setInteractionHeld(presented)
            // The context menu gates the hover previews: the dwell timer still fires
            // while the menu tracks (GCD main-queue work runs in the event-tracking
            // run-loop mode), so without this a window peek or folder stack pops up
            // *over* the open menu. Close anything open, cancel the pending dwell,
            // and resume normal hover behavior once the menu dismisses.
            self.contextMenuOpen = presented
            if presented {
                self.peekWork?.cancel()
                self.windowPeek.hide()
                self.folderStack.close()
            } else {
                self.scheduleApplyPreview()
            }
        }
        model.onReorder = { [weak self] orderedIDs in self?.reorder(to: orderedIDs) }
        model.onDragOutRemove = { [weak self] id in self?.removeItemWithPoof(id) }
        model.onAddDroppedItems = { [weak self] urls in self?.pinDroppedURLs(urls) }
        model.onHoverTile = { [weak self] tile, entered in self?.handleTileHover(tile, entered: entered) }
        // A popover close can bypass the hover path entirely (outside click, Escape,
        // selection) — always release the dock hold from the popover's own callback.
        windowPeek.onOpenChange = { [weak self] open in if !open { self?.releasePreviewDock() } }
        folderStack.onOpenChange = { [weak self] open in if !open { self?.releasePreviewDock() } }
    }

    // MARK: Hover previews (app windows / folder contents)

    /// The display whose dock is being held revealed while a hover-preview popover
    /// (window peek / folder stack) is open on it. Without the hold, crossing the gap
    /// from tile to popover leaves the dock's hover region and the auto-hide timer
    /// slides the dock away mid-interaction (flicker loop).
    private var previewHeldPanelUUID: String?

    private func holdPreviewDock(uuid: String) {
        guard previewHeldPanelUUID != uuid else { return }
        releasePreviewDock()
        previewHeldPanelUUID = uuid
        panels[uuid]?.setInteractionHeld(true)
    }

    private func releasePreviewDock() {
        guard let uuid = previewHeldPanelUUID else { return }
        previewHeldPanelUUID = nil
        panels[uuid]?.setInteractionHeld(false)
    }

    /// The tile the pointer is currently over that offers a hover preview (nil → none),
    /// coalesced so that moving between tiles — which fires an exit and an enter in either
    /// order — settles on the latest intent before we act (no flicker-close-then-reopen).
    private var hoveredPreviewTile: DockTile?

    /// True while a tile's context menu is up. Hover previews are suppressed for the
    /// duration so they can't appear over the menu; the presentation callback
    /// reschedules them when the menu dismisses.
    private var contextMenuOpen = false

    /// The kind of preview a tile shows on hover, or nil if it shows none.
    private enum HoverPreview { case windows, folder }
    private func hoverPreview(for tile: DockTile) -> HoverPreview? {
        switch tile.kind {
        case .application:
            guard preferences.windowPreviewMode != .off, tile.isRunning, pid(for: tile) != nil else { return nil }
            return .windows
        case .folder:
            return liveURL(for: tile) != nil ? .folder : nil
        default:
            return nil
        }
    }

    /// Hover entered/left a tile: show that tile's preview (a running app's windows, or a
    /// folder's contents) after a short dwell. Clicking still opens the tile — a folder
    /// opens in Finder — so both are available. Mirrors the window-peek dwell/grace so
    /// moving into the popover keeps it up.
    private func handleTileHover(_ tile: DockTile, entered: Bool) {
        if entered {
            guard hoverPreview(for: tile) != nil else { return }
            hoveredPreviewTile = tile
        } else if hoveredPreviewTile?.id == tile.id {
            hoveredPreviewTile = nil      // only clear when *this* tile is the one we're tracking
        }
        scheduleApplyPreview()
    }

    private func scheduleApplyPreview() {
        peekWork?.cancel()
        // Retarget an already-open preview almost immediately; require a short dwell
        // before the first open so a quick pass over the dock doesn't pop one.
        let anyOpen = windowPeek.isOpen || folderStack.isOpen
        let work = DispatchWorkItem { [weak self] in self?.applyPreview() }
        peekWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + (anyOpen ? 0.06 : 0.45), execute: work)
    }

    private func applyPreview() {
        guard !contextMenuOpen else { return }
        guard let tile = hoveredPreviewTile, let kind = hoverPreview(for: tile) else {
            windowPeek.scheduleHide()
            folderStack.scheduleHide()
            return
        }
        // Only one preview at a time — switching kinds dismisses the other immediately.
        switch kind {
        case .windows:
            folderStack.close()
            guard let pid = pid(for: tile) else { windowPeek.scheduleHide(); return }
            presentWindowPeek(tile: tile, pid: pid)
        case .folder:
            windowPeek.hide()
            presentFolderStack(for: tile)
        }
    }

    private func presentWindowPeek(tile: DockTile, pid: pid_t) {
        let mouse = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) ?? NSScreen.main else { return }
        let uuid = registry.key(for: screen)
        let edge = effectiveAnchor(forUUID: uuid).edge
        let dock = panels[uuid]?.revealedDockStripFrame ?? CGRect(origin: mouse, size: .zero)
        // Anchor to the app's icon (not the cursor) so the selector doesn't track the mouse.
        let anchor = tileAnchor(for: tile, edge: edge, dock: dock) ?? mouse
        let name = tile.displayName.isEmpty ? "Windows" : tile.displayName
        windowPeek.show(pid: pid, appName: name, near: anchor, dock: dock,
                        screen: screen, edge: edge, mode: preferences.windowPreviewMode)
        if windowPeek.isOpen { holdPreviewDock(uuid: uuid) }
    }

    /// The screen-space centre of `tile`'s icon along the dock axis, so the peek anchors
    /// to the app rather than the pointer. Mirrors `DockView.tileCenters` plus the
    /// centred slot-stack layout (magnification headroom `extra` + leading padding).
    private func tileAnchor(for tile: DockTile, edge: DockEdge, dock: CGRect) -> CGPoint? {
        let base = CGFloat(preferences.iconSize)
        let spacing = CGFloat(preferences.tileSpacing)
        let clockFactor = DockLayout.clockTileWidthFactor(zoom: CGFloat(preferences.effectiveClockZoom),
                                                          face: preferences.clockFace)
        var cursor: CGFloat = 0
        var centerAlong: CGFloat?
        for t in model.tiles {
            let extent = DockLayout.tileExtent(kind: t.kind, baseSize: base, edge: edge,
                                               clockWidthFactor: clockFactor).along
            if t.id == tile.id { centerAlong = cursor + extent / 2; break }
            cursor += extent + spacing
        }
        guard let centerAlong else { return nil }
        // The same along-axis headroom the panel budgets (widest tile), so the anchor
        // stays aligned with the centered content — keep in sync with `activeGlows`.
        let widest = edge.isHorizontal
            ? DockLayout.widestTileFactor(kinds: model.tiles.map(\.kind), clockWidthFactor: clockFactor) : 1
        let extra = DockLayout.magnificationAlongExtra(iconSize: base,
                                                       magnification: preferences.effectiveMagnification,
                                                       widestFactor: widest)
        let leading = extra / 2 + DockView.padding
        switch edge {
        case .bottom, .top: return CGPoint(x: dock.minX + leading + centerAlong, y: dock.midY)
        case .left, .right: return CGPoint(x: dock.midX, y: dock.maxY - (leading + centerAlong))
        }
    }

    /// The process id behind a running app tile (running-only tiles carry it directly;
    /// pinned-and-running ones resolve it from the bundle id).
    private func pid(for tile: DockTile) -> pid_t? {
        if let pid = tile.pid { return pid }
        if let bundleID = tile.bundleIdentifier,
           let running = runningApps.runningApplication(bundleIdentifier: bundleID) {
            return running.processIdentifier
        }
        return nil
    }

    /// Pins file/folder/app URLs dropped onto the dock strip or the edge drag-sensor,
    /// skipping any already-pinned target so a repeat drop doesn't duplicate a tile.
    private func pinDroppedURLs(_ urls: [URL]) {
        for url in urls where !isAlreadyPinned(url) {
            store.addItem(makePinnedItem(for: url))
        }
    }

    /// Removes a pinned item with the nostalgic Dock "poof" at the pointer (ND-5).
    private func removeItemWithPoof(_ id: UUID) {
        Poof.play(at: NSEvent.mouseLocation)
        store.removeItem(id: id)
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

    /// The tile's *live* URL — resolved through the store's bookmark (so a moved
    /// file/app is found) with the freshened bookmark persisted (ISSUE-7), falling
    /// back to the tile's stored URL for running-only tiles with no backing item.
    private func liveURL(for tile: DockTile) -> URL? {
        if let id = tile.itemID, let url = store.resolvedURL(forItemID: id) { return url }
        return tile.url
    }

    private func open(_ tile: DockTile) {
        // A click dismisses any hover-opened folder stack. A folder opens in Finder like
        // a file — its contents are previewed on hover instead of on click.
        folderStack.close()
        // Cmd-click is the "Show in Finder" shortcut, like the system Dock. Prefer
        // the click event's own flags over polling the hardware state, so a quick
        // Cmd-tap still counts even if the key is released before this runs.
        let commandDown = NSApp.currentEvent?.modifierFlags.contains(.command)
            ?? NSEvent.modifierFlags.contains(.command)
        if commandDown, let url = showInFinderURL(for: tile) {
            revealInFinder(url)
            return
        }
        switch tile.kind {
        case .application:
            openApplication(tile)
        case .file, .folder, .url:
            if let url = liveURL(for: tile) { NSWorkspace.shared.open(url) }
        case .trash:
            AppLauncher.openTrash()
        case .clock:
            openCalendar()
        case .worldClock:
            openClock()
        case .battery:
            openURLString("x-apple.systempreferences:com.apple.preference.battery")
        case .systemMonitor:
            openActivityMonitor()
        case .weather:
            // Honor the offline glyph's "tap to retry" tooltip: while the weather is
            // unavailable, a tap retries the fetch instead of opening the Weather app
            // (FAB-B19). `isUnavailable` matches exactly the state that shows the glyph.
            let weather = WeatherService.shared
            if weather.isUnavailable(latitude: preferences.weatherLatitude,
                                     longitude: preferences.weatherLongitude,
                                     celsius: preferences.weatherUseCelsius) {
                weather.refresh(latitude: preferences.weatherLatitude,
                                longitude: preferences.weatherLongitude,
                                celsius: preferences.weatherUseCelsius)
            } else {
                openWeatherApp()
            }
        case .nowPlaying:
            openMusicApp()
        case .pomodoro:
            PomodoroTimer.shared.tap()
            return   // the timer toggles in place; keep the dock as-is
        case .jettyMenu:
            openJettyMenu(from: tile)
            return   // don't hide the dock; the menu is its own panel
        case .separator, .runningApps:
            return
        }
        // Don't hide on click — the dock stays put until the pointer leaves it, then the
        // auto-hide pointer-tracking takes over. Hiding on launch felt abrupt.
    }

    private func openApplication(_ tile: DockTile) {
        let appURL = liveURL(for: tile) ?? tile.bundleIdentifier.flatMap { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) }
        if let appURL {
            let name = tile.displayName.isEmpty ? appURL.deletingPathExtension().lastPathComponent : tile.displayName
            RecentAppsStore.shared.record(name: name, bundleID: tile.bundleIdentifier, url: appURL)
        }
        if let bundleID = tile.bundleIdentifier,
           let running = runningApps.runningApplication(bundleIdentifier: bundleID) {
            AppLauncher.activate(running)
        } else if let appURL {
            AppLauncher.launchApplication(at: appURL)
        } else if let pid = tile.pid, let running = runningApps.runningApplication(pid: pid) {
            // Bundle-less running app (no bundle id or app URL) → activate by PID (ISSUE-1).
            AppLauncher.activate(running)
        }
    }

    /// Shows the folder-stack contents popover for a folder tile (on hover, or from the
    /// context menu), anchored to the tile on the screen it's on and oriented to that
    /// display's dock edge (MF-2).
    private func presentFolderStack(for tile: DockTile) {
        guard let url = liveURL(for: tile) else { return }
        let mouse = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) ?? NSScreen.main else { return }
        let uuid = registry.key(for: screen)
        let edge = effectiveAnchor(forUUID: uuid).edge
        // Place the popover clear of the dock strip, anchored to the folder's icon (like
        // the window-peek) so it sits above the tile rather than tracking the cursor.
        let dock = panels[uuid]?.revealedDockStripFrame ?? CGRect(origin: mouse, size: .zero)
        let anchor = tileAnchor(for: tile, edge: edge, dock: dock) ?? mouse
        folderStack.show(folder: url, style: tile.folderDisplay ?? .grid,
                         near: anchor, dock: dock, screen: screen, edge: edge)
        if folderStack.isOpen { holdPreviewDock(uuid: uuid) }
    }

    private func handleDrop(_ urls: [URL], on tile: DockTile) {
        switch tile.kind {
        case .application:
            if let appURL = tile.url ?? tile.bundleIdentifier.flatMap({ NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) }) {
                AppLauncher.open(urls, withApplicationAt: appURL)
            }
        case .trash:
            if AppLauncher.moveToTrash(urls) > 0 {
                // Our own action changed the Trash — resolve immediately rather
                // than waiting on the vnode watch.
                refreshTrashState()
            }
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

    private static func isTrashItem(_ item: DockItem) -> Bool {
        item.kind == .trash || item.url.map(TrashLocations.isTrashURL) == true
    }

    /// Whether a file/folder URL is already pinned (compared by standardized path).
    private func isAlreadyPinned(_ url: URL) -> Bool {
        if TrashLocations.isTrashURL(url) {
            return store.items.contains(where: Self.isTrashItem)
        }
        let target = url.standardizedFileURL
        return store.items.contains { $0.url?.standardizedFileURL == target }
    }

    // MARK: Context menu

    private func contextActions(for tile: DockTile) -> [DockContextAction] {
        var actions: [DockContextAction] = []
        switch tile.kind {
        case .application:
            let bundleID = tile.bundleIdentifier
            let appURL = tile.url ?? bundleID.flatMap {
                NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0)
            }
            let running = runningApplication(for: tile)
            if let running {
                actions.append(DockContextAction(title: "Show") { AppLauncher.activate(running) })
                actions.append(DockContextAction(title: running.isHidden ? "Unhide" : "Hide") {
                    if running.isHidden { running.unhide() } else { running.hide() }
                })
                actions.append(DockContextAction(title: "Quit", isDestructive: true) {
                    AppLauncher.quit(running)
                })
                actions.append(forceQuitAction(for: running, name: tile.displayName))
                actions.append(.separator)
            } else {
                actions.append(DockContextAction(title: "Open") { [weak self] in self?.openApplication(tile) })
            }
            if let itemID = tile.itemID {
                actions.append(DockContextAction(title: "Remove from Dock", isDestructive: true) { [weak self] in
                    self?.removeItemWithPoof(itemID)
                })
            } else if appURL != nil {
                actions.append(DockContextAction(title: "Keep in Dock") { [weak self] in self?.pin(tile) })
            }
            if let appURL {
                actions.append(DockContextAction(title: "Show in Finder") { [weak self] in
                    self?.revealInFinder(appURL)
                })
            }
        case .file, .folder, .url:
            actions.append(DockContextAction(title: tile.kind == .folder ? "Open in Finder" : "Open") { [weak self] in self?.open(tile) })
            if tile.kind == .folder {
                actions.append(DockContextAction(title: "Show Contents") { [weak self] in self?.presentFolderStack(for: tile) })
            }
            if let url = tile.url, url.isFileURL {
                actions.append(DockContextAction(title: "Show in Finder") { [weak self] in
                    self?.revealInFinder(url)
                })
            }
            if let itemID = tile.itemID {
                actions.append(.separator)
                actions.append(DockContextAction(title: "Remove from Dock", isDestructive: true) { [weak self] in
                    self?.removeItemWithPoof(itemID)
                })
            }
        case .trash:
            actions.append(DockContextAction(title: "Open Trash") { AppLauncher.openTrash() })
            actions.append(DockContextAction(title: "Empty Trash…", isDestructive: true) { [weak self] in
                self?.confirmAndEmptyTrash()
            })
        case .clock:
            actions.append(DockContextAction(title: "Open Calendar") { [weak self] in self?.openCalendar() })
        case .worldClock:
            actions.append(DockContextAction(title: "Open Clock") { [weak self] in self?.openClock() })
        case .battery:
            actions.append(DockContextAction(title: "Open Battery Settings") { [weak self] in
                self?.openURLString("x-apple.systempreferences:com.apple.preference.battery")
            })
        case .systemMonitor:
            actions.append(DockContextAction(title: "Open Activity Monitor") { [weak self] in self?.openActivityMonitor() })
        case .weather:
            actions.append(DockContextAction(title: "Open Weather") { [weak self] in self?.openWeatherApp() })
        case .nowPlaying:
            actions.append(DockContextAction(title: "Open Music") { [weak self] in self?.openMusicApp() })
        case .pomodoro:
            actions.append(DockContextAction(title: PomodoroTimer.shared.isRunning ? "Pause" : "Start") {
                PomodoroTimer.shared.tap()
            })
            actions.append(DockContextAction(title: "Reset") { PomodoroTimer.shared.reset() })
        case .jettyMenu:
            actions.append(DockContextAction(title: "Open Jetty Menu") { [weak self] in self?.openJettyMenu(from: tile) })
        case .separator, .runningApps:
            break
        }
        return actions
    }

    /// The on-disk target a Cmd-click reveals in Finder — the same URL the context
    /// menu's "Show in Finder" action uses, so both paths stay in sync (apps resolve
    /// through the live/bookmark URL like launching does).
    private func showInFinderURL(for tile: DockTile) -> URL? {
        switch tile.kind {
        case .application:
            if let url = liveURL(for: tile), url.isFileURL { return url }
            return tile.bundleIdentifier.flatMap {
                NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0)
            }
        case .file, .folder, .url:
            let url = liveURL(for: tile)
            return url?.isFileURL == true ? url : nil
        default:
            return nil
        }
    }

    /// Reveals `url` in Finder; if the target was moved/trashed since resolution,
    /// reveals its parent folder instead of failing silently.
    private func revealInFinder(_ url: URL) {
        let target = FileManager.default.fileExists(atPath: url.path)
            ? url : url.deletingLastPathComponent()
        NSWorkspace.shared.activateFileViewerSelecting([target])
    }

    private func runningApplication(for tile: DockTile) -> NSRunningApplication? {
        if let pid = tile.pid {
            return runningApps.runningApplication(pid: pid)
        }
        return tile.bundleIdentifier.flatMap {
            runningApps.runningApplication(bundleIdentifier: $0)
        }
    }

    private func forceQuitAction(for application: NSRunningApplication,
                                 name: String) -> DockContextAction {
        DockContextAction(title: "Force Quit…", isDestructive: true) { [weak self] in
            self?.confirmForceQuit(application, name: name)
        }
    }

    private func confirmForceQuit(_ application: NSRunningApplication, name: String) {
        let appName = name.isEmpty ? (application.localizedName ?? "this app") : name
        let appToRestore = NSWorkspace.shared.frontmostApplication
        var forceQuitAccepted = false
        defer {
            if let appToRestore, !appToRestore.isTerminated,
               !(forceQuitAccepted && appToRestore.processIdentifier == application.processIdentifier) {
                AppLauncher.activate(appToRestore)
            } else if let finder = NSRunningApplication.runningApplications(
                withBundleIdentifier: "com.apple.finder").first {
                AppLauncher.activate(finder)
            }
        }
        let alert = NSAlert()
        alert.messageText = "Force Quit \(appName)?"
        alert.informativeText = "The app will quit immediately. Unsaved changes will be lost."
        alert.addButton(withTitle: "Force Quit")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn, !application.isTerminated else { return }
        guard AppLauncher.forceQuit(application) else {
            let failure = NSAlert()
            failure.messageText = "Could Not Force Quit \(appName)"
            failure.informativeText = "The app may already have quit, or macOS refused the request."
            failure.addButton(withTitle: "OK")
            failure.runModal()
            runningApps.refresh()
            return
        }
        forceQuitAccepted = true
    }

    private func confirmAndEmptyTrash() {
        let alert = NSAlert()
        alert.messageText = "Empty Trash?"
        alert.informativeText = "Are you sure you want to permanently empty the Trash?"
        alert.addButton(withTitle: "Empty Trash")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        PowerCommandRunner.run(.emptyTrash)
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

    /// (Re)registers the user-configurable global hotkeys from preferences. A
    /// disabled or modifier-less binding is unregistered rather than registered, so
    /// the user can turn a shortcut off entirely (MF-6).
    private func registerHotkeys() {
        let toggle = preferences.toggleHotkey
        if toggle.isValid {
            toggleHotkey.onPressed = { [weak self] in self?.toggleAllDocks() }
            toggleHotkey.register(keyCode: toggle.keyCode, modifiers: toggle.modifiers)
        } else {
            toggleHotkey.unregister()
        }

        let menu = preferences.menuHotkey
        if menu.isValid {
            menuHotkey.onPressed = { [weak self] in self?.openJettyMenu() }
            menuHotkey.register(keyCode: menu.keyCode, modifiers: menu.modifiers)
        } else {
            menuHotkey.unregister()
        }
    }

    /// Global toggle: if *any* panel is revealed, hide them all; otherwise reveal them
    /// all. Toggling each panel independently would swap mixed states (hide the one the
    /// pointer revealed while revealing the rest) — not what the user means (M34).
    func toggleAllDocks() {
        if panels.values.contains(where: { $0.isRevealed }) {
            panels.values.forEach { $0.hideForToggle() }
        } else {
            panels.values.forEach { $0.reveal() }
        }
    }

    func openJettyMenu() {
        // Open on the screen the pointer is on (where the Jetty button was clicked, or
        // where the menu hotkey was pressed), not always the primary display.
        let point = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(point, $0.frame, false) }
            ?? NSScreen.main ?? NSScreen.screens.first
        jettyMenu.toggle(on: screen)
    }

    /// Opens the menu anchored next to the clicked Jetty tile, like a pop-up menu.
    /// The hotkey / status-item paths use `openJettyMenu()`, which centers it.
    private func openJettyMenu(from tile: DockTile) {
        let mouse = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) })
            ?? NSScreen.main else { openJettyMenu(); return }
        let uuid = registry.key(for: screen)
        let edge = effectiveAnchor(forUUID: uuid).edge
        let dock = panels[uuid]?.revealedDockStripFrame ?? CGRect(origin: mouse, size: .zero)
        // Anchor to the tile's icon (not the cursor), mirroring the hover previews.
        let anchor = tileAnchor(for: tile, edge: edge, dock: dock) ?? mouse
        jettyMenu.toggle(on: screen,
                         from: .init(point: anchor, dockFrame: dock, edge: edge))
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

    /// Opens the system Clock app (world-clock tile), falling back to Calendar.
    private func openClock() {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.clock") {
            AppLauncher.launchApplication(at: url)
        } else {
            openCalendar()
        }
    }

    /// Opens Activity Monitor (system-monitor tile).
    private func openActivityMonitor() {
        let path = "/System/Applications/Utilities/Activity Monitor.app"
        if FileManager.default.fileExists(atPath: path) {
            AppLauncher.launchApplication(at: URL(fileURLWithPath: path))
        }
    }

    /// Opens the Weather app (weather tile), falling back to a web forecast.
    private func openWeatherApp() {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.weather") {
            AppLauncher.launchApplication(at: url)
        } else {
            openURLString("https://weather.com")
        }
    }

    /// Opens the Music app (now-playing tile).
    private func openMusicApp() {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Music") {
            AppLauncher.launchApplication(at: url)
        }
    }

    private func openURLString(_ string: String) {
        if let url = URL(string: string) { NSWorkspace.shared.open(url) }
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
