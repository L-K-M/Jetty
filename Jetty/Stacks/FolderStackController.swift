import AppKit
import SwiftUI

/// Presents a folder-stack popover near a clicked folder tile: a borderless,
/// non-activating panel floating over content (matching the dock's overlay model).
/// Contents load off the main thread; subfolders drill in; a file opens normally.
/// Dismisses on Escape, on a click anywhere outside it, or when another tile is
/// opened. See MF-2 / PLAN.md §6.
final class FolderStackController {

    private let preferences: Preferences
    private var panel: NSPanel?
    private var model: FolderStackModel?
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var keyMonitor: Any?
    private(set) var isOpen = false
    private var rootFolder: URL?

    /// Hover lifecycle (the stack is opened by hovering a folder tile): a pending hide is
    /// cancelled when the pointer moves into the popover, so it stays up while browsed.
    private var hideWork: DispatchWorkItem?
    private var hoveringPanel = false

    init(preferences: Preferences) {
        self.preferences = preferences
    }

    /// Shows the stack for `folder` (hover-driven). Re-showing the folder that's already
    /// on screen just keeps it up (cancelling a pending hide), so hover jitter doesn't
    /// rebuild and flicker the popover; a different folder rebuilds.
    func show(folder: URL, style: FolderStackStyle, near point: CGPoint, dock: CGRect, screen: NSScreen, edge: DockEdge) {
        hideWork?.cancel(); hideWork = nil
        if isOpen, rootFolder == folder { return }
        close()

        let model = FolderStackModel(style: style)
        let root = FolderStackView(
            model: model, preferences: preferences,
            onSelect: { [weak self] entry in self?.select(entry) },
            onBack: { model.goBack() },
            onOpenInFinder: { [weak self] in self?.openInFinder() },
            onHoverChange: { [weak self] inside in
                self?.hoveringPanel = inside
                if !inside { self?.scheduleHide() }
            })

        let size = FolderStack.panelSize(style: style)
        let hosting = NSHostingController(rootView: root)
        hosting.view.frame = CGRect(origin: .zero, size: size)

        let panel = NSPanel(contentViewController: hosting)
        panel.styleMask = [.borderless, .nonactivatingPanel]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        // A hair above the dock panels (also .popUpMenu) so it never hides behind them.
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.popUpMenu.rawValue + 1)
        panel.isReleasedWhenClosed = false
        panel.isMovable = false
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.setContentSize(size)
        panel.setFrameOrigin(FolderStack.origin(for: size, near: point, dock: dock, edge: edge, in: screen.visibleFrame))
        panel.orderFrontRegardless()

        self.panel = panel
        self.model = model
        rootFolder = folder
        isOpen = true
        model.open(folder)          // kicks the async load; the glass panel shows immediately
        installMonitors()
    }

    func close() {
        hideWork?.cancel(); hideWork = nil
        guard isOpen else { return }
        isOpen = false
        hoveringPanel = false
        rootFolder = nil
        model = nil
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor); self.globalMonitor = nil }
        if let localMonitor { NSEvent.removeMonitor(localMonitor); self.localMonitor = nil }
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor); self.keyMonitor = nil }
        panel?.orderOut(nil)
        panel = nil
    }

    /// Hides after a short grace period unless the pointer moved into the popover — so a
    /// hover-opened stack survives the gap between the folder tile and the popover.
    func scheduleHide() {
        hideWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, !self.hoveringPanel else { return }
            self.close()
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    // MARK: Actions

    /// A subfolder drills in; a file (or alias/bundle) opens and closes the stack.
    /// Drillability keys off `.isPackageKey`, not the path extension, so ordinary
    /// folders with dotted names (`jquery-3.7.1`, `My.Project`) drill in (FAB-B6).
    private func select(_ entry: FolderEntry) {
        if FolderStack.isDrillable(entry) {
            model?.open(entry.url)
        } else {
            NSWorkspace.shared.open(entry.url)
            close()
        }
    }

    private func openInFinder() {
        if let folder = model?.currentFolder ?? rootFolder { NSWorkspace.shared.open(folder) }
        close()
    }

    private func installMonitors() {
        // A click in any other app/window dismisses the stack (Spotlight-style).
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.close()
        }
        // A click that lands on one of Jetty's *own* windows (e.g. the dock, which the
        // popover opens right next to) isn't seen by the global monitor — so also watch
        // local clicks and dismiss when they fall outside the popover itself.
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self, let panel = self.panel else { return event }
            if !panel.frame.contains(NSEvent.mouseLocation) { self.close() }
            return event
        }
        // Escape dismisses while Jetty has focus; harmless otherwise.
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { self?.close(); return nil }
            return event
        }
    }
}
