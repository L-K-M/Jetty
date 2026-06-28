import AppKit
import SwiftUI

/// Presents the window-peek popover when a running app's tile is hovered: a borderless,
/// non-activating panel of live window thumbnails, floating clear of the dock. Clicking
/// a thumbnail raises that window; the corner button minimizes it. Dismisses when the
/// pointer leaves both the tile and the popover, on selecting a window, or on an
/// outside click. See PLAN.md §12.
final class WindowPeekController {

    private let preferences: Preferences
    private let model = WindowPeekModel()
    private var panel: NSPanel?
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private(set) var currentPID: pid_t?

    private var hideWork: DispatchWorkItem?
    private var hoveringPanel = false

    init(preferences: Preferences) { self.preferences = preferences }

    var isOpen: Bool { panel != nil }

    /// Shows (or re-targets) the popover for `pid`. Does nothing if the app has no
    /// listable on-screen windows.
    func show(pid: pid_t, appName: String, near point: CGPoint, dock: CGRect, screen: NSScreen, edge: DockEdge) {
        hideWork?.cancel(); hideWork = nil
        let wins = WindowLister.windows(forPID: pid)
        guard !wins.isEmpty else { hide(); return }

        let size = panelSize(count: wins.count, screen: screen)
        let panel = self.panel ?? makePanel()
        self.panel = panel
        if currentPID != pid {
            currentPID = pid
            model.load(pid: pid, appName: appName)
        }
        panel.setContentSize(size)
        panel.setFrameOrigin(origin(size: size, near: point, dock: dock, edge: edge, in: screen.visibleFrame))
        panel.orderFrontRegardless()
        installMonitors()
    }

    /// Hides after a short grace period unless the pointer moved into the popover.
    func scheduleHide() {
        hideWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, !self.hoveringPanel else { return }
            self.hide()
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    func hide() {
        hideWork?.cancel(); hideWork = nil
        guard panel != nil else { return }
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor); self.globalMonitor = nil }
        if let localMonitor { NSEvent.removeMonitor(localMonitor); self.localMonitor = nil }
        model.stop()
        panel?.orderOut(nil)
        panel = nil
        currentPID = nil
        hoveringPanel = false
    }

    // MARK: Build

    private func makePanel() -> NSPanel {
        let hosting = NSHostingController(rootView: WindowPeekView(
            model: model, preferences: preferences,
            onSelect: { [weak self] window in WindowActions.raise(window); self?.hide() },
            onMinimize: { [weak self] window in WindowActions.minimize(window); self?.hideIfEmptySoon() },
            onHoverChange: { [weak self] inside in
                self?.hoveringPanel = inside
                if !inside { self?.scheduleHide() }
            }))
        let panel = NSPanel(contentViewController: hosting)
        panel.styleMask = [.borderless, .nonactivatingPanel]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.popUpMenu.rawValue + 1)
        panel.isReleasedWhenClosed = false
        panel.isMovable = false
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        return panel
    }

    /// After a minimize the window may be gone; close the popover if nothing remains.
    private func hideIfEmptySoon() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            guard let self, let pid = self.currentPID else { return }
            if WindowLister.windows(forPID: pid).isEmpty { self.hide() }
        }
    }

    private func installMonitors() {
        if globalMonitor == nil {
            globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
                self?.hide()
            }
        }
        // A click on one of Jetty's own windows (e.g. the dock) isn't seen by the global
        // monitor — dismiss when a local click lands outside the popover itself.
        if localMonitor == nil {
            localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
                guard let self, let panel = self.panel else { return event }
                if !panel.frame.contains(NSEvent.mouseLocation) { self.hide() }
                return event
            }
        }
    }

    // MARK: Geometry

    private func panelSize(count: Int, screen: NSScreen) -> CGSize {
        let estimatedPerWindow: CGFloat = 190     // thumbnail + spacing
        let width = min(max(CGFloat(count) * estimatedPerWindow + 24, 240),
                        screen.visibleFrame.width - 40)
        return CGSize(width: width, height: 200)
    }

    private func origin(size: CGSize, near point: CGPoint, dock: CGRect, edge: DockEdge, in vf: CGRect) -> CGPoint {
        let margin: CGFloat = 6
        var x = point.x - size.width / 2
        var y = point.y - size.height / 2
        switch edge {
        case .bottom: y = dock.maxY + margin
        case .top:    y = dock.minY - size.height - margin
        case .left:   x = dock.maxX + margin
        case .right:  x = dock.minX - size.width - margin
        }
        x = min(max(x, vf.minX + 8), vf.maxX - size.width - 8)
        y = min(max(y, vf.minY + 8), vf.maxY - size.height - 8)
        return CGPoint(x: x, y: y)
    }
}
