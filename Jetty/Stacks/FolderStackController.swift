import AppKit
import SwiftUI

/// Presents a folder-stack popover near a clicked folder tile: a borderless,
/// non-activating panel floating over content (matching the dock's overlay model).
/// Dismisses on Escape, on a click anywhere outside it, or when another tile is
/// opened. See MF-2 / PLAN.md §6.
final class FolderStackController {

    private let preferences: Preferences
    private var panel: NSPanel?
    private var globalMonitor: Any?
    private var keyMonitor: Any?
    private(set) var isOpen = false
    private var currentFolder: URL?

    init(preferences: Preferences) {
        self.preferences = preferences
    }

    /// Opens the stack for `folder`, or closes it if it's already showing that folder.
    func toggle(folder: URL, style: FolderStackStyle, near point: CGPoint, screen: NSScreen, edge: DockEdge) {
        if isOpen, currentFolder == folder { close(); return }
        show(folder: folder, style: style, near: point, screen: screen, edge: edge)
    }

    func show(folder: URL, style: FolderStackStyle, near point: CGPoint, screen: NSScreen, edge: DockEdge) {
        close()
        let entries = FolderStack.entries(of: folder)
        let size = FolderStack.panelSize(style: style, count: entries.count)

        let root = FolderStackView(
            folderName: folder.lastPathComponent, entries: entries, style: style, preferences: preferences,
            onOpen: { [weak self] url in self?.open(url) },
            onOpenFolder: { [weak self] in self?.open(folder) })

        let hosting = NSHostingController(rootView: root)
        let panel = NSPanel(contentViewController: hosting)
        panel.styleMask = [.borderless, .nonactivatingPanel]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .popUpMenu
        panel.isReleasedWhenClosed = false
        panel.isMovable = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.setContentSize(size)
        panel.setFrameOrigin(FolderStack.origin(for: size, near: point, edge: edge, in: screen.visibleFrame))
        panel.orderFrontRegardless()

        self.panel = panel
        currentFolder = folder
        isOpen = true
        installMonitors()
    }

    func close() {
        guard isOpen else { return }
        isOpen = false
        currentFolder = nil
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor); self.globalMonitor = nil }
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor); self.keyMonitor = nil }
        panel?.orderOut(nil)
        panel = nil
    }

    private func open(_ url: URL) {
        NSWorkspace.shared.open(url)
        close()
    }

    private func installMonitors() {
        // A click in any other app/window dismisses the stack (Spotlight-style).
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.close()
        }
        // Escape dismisses while Jetty has focus; harmless otherwise.
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { self?.close(); return nil }
            return event
        }
    }
}
