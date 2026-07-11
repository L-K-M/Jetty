import AppKit
import SwiftUI

/// A transparent AppKit right-click source that gives Jetty explicit, edge-aware native
/// menu placement without intercepting normal clicks, drags, drops, or hover handling.
struct DockContextMenuSource: NSViewRepresentable {
    let edge: DockEdge
    let dockThickness: CGFloat
    let actions: () -> [DockContextAction]
    let onPresentationChanged: (Bool) -> Void
    let onPrimaryPressChanged: (Bool) -> Void

    func makeNSView(context: Context) -> DockContextMenuSourceView {
        let view = DockContextMenuSourceView()
        update(view)
        return view
    }

    func updateNSView(_ nsView: DockContextMenuSourceView, context: Context) {
        update(nsView)
    }

    static func dismantleNSView(_ nsView: DockContextMenuSourceView, coordinator: ()) {
        nsView.stopObservingPrimaryPress()
    }

    private func update(_ view: DockContextMenuSourceView) {
        view.edge = edge
        view.dockThickness = dockThickness
        view.actions = actions
        view.onPresentationChanged = onPresentationChanged
        view.onPrimaryPressChanged = onPrimaryPressChanged
    }
}

final class DockContextMenuSourceView: NSView {
    var edge: DockEdge = .bottom
    var dockThickness: CGFloat = 0
    var actions: (() -> [DockContextAction])?
    var onPresentationChanged: ((Bool) -> Void)?
    var onPrimaryPressChanged: ((Bool) -> Void)?

    private var actionTargets: [DockMenuActionTarget] = []
    private var primaryPressMonitor: Any?
    private var globalMouseUpMonitor: Any?
    private var isPrimaryPressed = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setAccessibilityElement(false)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        if let primaryPressMonitor { NSEvent.removeMonitor(primaryPressMonitor) }
        if let globalMouseUpMonitor { NSEvent.removeMonitor(globalMouseUpMonitor) }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        stopObservingPrimaryPress()
        guard window != nil else { return }
        primaryPressMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp]) { [weak self] event in
                self?.observePrimaryPress(event)
                return event
            }
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let event = NSApp.currentEvent else { return nil }
        if event.type == .rightMouseDown { return super.hitTest(point) }
        if event.type == .leftMouseDown, event.modifierFlags.contains(.control) {
            return super.hitTest(point)
        }
        return nil
    }

    override func rightMouseDown(with event: NSEvent) {
        presentMenu(for: event)
    }

    override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.control) { presentMenu(for: event) }
    }

    func stopObservingPrimaryPress() {
        if let primaryPressMonitor {
            NSEvent.removeMonitor(primaryPressMonitor)
            self.primaryPressMonitor = nil
        }
        setPrimaryPressed(false)
    }

    private func observePrimaryPress(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDown:
            guard !event.modifierFlags.contains(.control), event.window === window else {
                setPrimaryPressed(false)
                return
            }
            let localPoint = convert(event.locationInWindow, from: nil)
            setPrimaryPressed(bounds.contains(localPoint))
        case .leftMouseDragged:
            guard isPrimaryPressed, event.window === window else { return }
            let localPoint = convert(event.locationInWindow, from: nil)
            if !bounds.contains(localPoint) { setPrimaryPressed(false) }
        case .leftMouseUp:
            setPrimaryPressed(false)
        default:
            break
        }
    }

    private func setPrimaryPressed(_ pressed: Bool) {
        guard pressed != isPrimaryPressed else { return }
        isPrimaryPressed = pressed
        if pressed {
            globalMouseUpMonitor = NSEvent.addGlobalMonitorForEvents(
                matching: .leftMouseUp) { [weak self] _ in
                    DispatchQueue.main.async { self?.setPrimaryPressed(false) }
                }
        } else if let globalMouseUpMonitor {
            NSEvent.removeMonitor(globalMouseUpMonitor)
            self.globalMouseUpMonitor = nil
        }
        onPrimaryPressChanged?(pressed)
    }

    private func presentMenu(for event: NSEvent) {
        guard let window, let screen = window.screen else { return }
        let descriptors = actions?() ?? []
        guard descriptors.contains(where: { !$0.isSeparator }) else { return }

        let menu = NSMenu()
        menu.autoenablesItems = false
        actionTargets.removeAll(keepingCapacity: true)
        for descriptor in descriptors {
            if descriptor.isSeparator {
                menu.addItem(.separator())
                continue
            }
            let item = NSMenuItem(title: descriptor.title, action: nil, keyEquivalent: "")
            if let action = descriptor.action {
                let target = DockMenuActionTarget(action)
                actionTargets.append(target)
                item.target = target
                item.action = #selector(DockMenuActionTarget.performAction(_:))
            } else {
                item.isEnabled = false
            }
            menu.addItem(item)
        }

        menu.update()
        let sourcePoint = window.convertPoint(toScreen: event.locationInWindow)
        let dockFrame = DockContextMenuPlacement.dockStripFrame(
            panelFrame: window.frame, thickness: dockThickness, edge: edge)
        let point = DockContextMenuPlacement.topLeft(
            menuSize: menu.size, sourcePoint: sourcePoint, dockFrame: dockFrame,
            visibleFrame: screen.visibleFrame, edge: edge)

        onPresentationChanged?(true)
        defer {
            onPresentationChanged?(false)
            actionTargets.removeAll(keepingCapacity: true)
        }
        _ = menu.popUp(positioning: nil, at: point, in: nil)
    }
}

private final class DockMenuActionTarget: NSObject {
    private let action: () -> Void

    init(_ action: @escaping () -> Void) {
        self.action = action
    }

    @objc func performAction(_ sender: Any?) {
        action()
    }
}
