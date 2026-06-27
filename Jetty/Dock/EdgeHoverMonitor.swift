import AppKit

/// Watches the pointer (global + local **mouse** monitors — which need *no*
/// permission, unlike a key/event tap) and reports its screen location so the dock
/// can reveal when the pointer reaches its edge and hide when it leaves. See
/// PLAN.md §2, §4.
final class EdgeHoverMonitor {

    /// Called on the main thread with the pointer's global screen location whenever
    /// it moves.
    var onMove: ((NSPoint) -> Void)?

    private var globalMonitor: Any?
    private var localMonitor: Any?

    func start() {
        guard globalMonitor == nil else { return }
        let mask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .rightMouseDragged]
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] _ in
            self?.onMove?(NSEvent.mouseLocation)
        }
        // A local monitor covers the case where Jetty itself is the active app
        // (global monitors don't fire for the active app's own events).
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            self?.onMove?(NSEvent.mouseLocation)
            return event
        }
    }

    func stop() {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        globalMonitor = nil
        localMonitor = nil
    }

    deinit { stop() }
}
