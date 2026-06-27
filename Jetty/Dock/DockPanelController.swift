import AppKit
import SwiftUI
import QuartzCore

/// An `NSHostingView` that accepts the first mouse click even when its window is
/// not key, so a click on the (background-app) dock registers immediately.
private final class DockHostingView: NSHostingView<DockView> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// Owns one display's auto-hiding dock panel: a borderless, non-activating,
/// always-on-top window that floats **over** content on reveal (no screen-space
/// reservation). Reveal/hide is driven by the pointer location forwarded from the
/// `EdgeHoverMonitor`, or by an explicit toggle. See PLAN.md §4.
@MainActor
final class DockPanelController {

    let displayUUID: String
    private let model: DockModel
    private let preferences: Preferences
    private let panel: NSPanel
    private let hostingView: DockHostingView

    private(set) var screen: NSScreen
    private(set) var anchor: DockAnchor
    private(set) var isRevealed = false

    private var revealWork: DispatchWorkItem?
    private var hideWork: DispatchWorkItem?

    init(displayUUID: String, screen: NSScreen, anchor: DockAnchor,
         model: DockModel, preferences: Preferences) {
        self.displayUUID = displayUUID
        self.screen = screen
        self.anchor = anchor
        self.model = model
        self.preferences = preferences

        hostingView = DockHostingView(rootView: DockView(model: model, preferences: preferences))
        hostingView.translatesAutoresizingMaskIntoConstraints = true
        hostingView.autoresizingMask = [.width, .height]

        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 200, height: 80),
                        styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .popUpMenu
        panel.isMovable = false
        panel.isReleasedWhenClosed = false
        panel.isRestorable = false
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]

        let container = NSView(frame: NSRect(x: 0, y: 0, width: 200, height: 80))
        container.autoresizesSubviews = true
        hostingView.frame = container.bounds
        container.addSubview(hostingView)
        panel.contentView = container
    }

    // MARK: Configuration

    func update(screen: NSScreen, anchor: DockAnchor) {
        self.screen = screen
        self.anchor = anchor
        layoutForCurrentState()
    }

    /// Recomputes the frame for the current revealed/hidden state (call after the
    /// tile set or appearance changes).
    func layoutForCurrentState() {
        let frame = isRevealed ? revealedFrame() : hiddenFrame()
        panel.setFrame(frame, display: true)
        if !panel.isVisible { panel.orderFrontRegardless() }
    }

    func showInitial() {
        if preferences.autoHide {
            isRevealed = false
            panel.setFrame(hiddenFrame(), display: false)
        } else {
            isRevealed = true
            panel.setFrame(revealedFrame(), display: false)
        }
        panel.orderFrontRegardless()
    }

    func close() {
        revealWork?.cancel(); hideWork?.cancel()
        panel.orderOut(nil)
    }

    // MARK: Reveal / hide

    func reveal(animated: Bool = true) {
        hideWork?.cancel(); hideWork = nil
        guard !isRevealed else { return }
        isRevealed = true
        setFrame(revealedFrame(), animated: animated)
    }

    func hide(animated: Bool = true) {
        revealWork?.cancel(); revealWork = nil
        guard isRevealed, preferences.autoHide else { return }
        isRevealed = false
        setFrame(hiddenFrame(), animated: animated)
    }

    func toggle() {
        if isRevealed { hide() } else { reveal() }
    }

    /// Pointer moved (global coordinates) — decide whether to reveal or hide.
    func handleMouseMoved(to point: NSPoint) {
        guard preferences.autoHide, preferences.revealTrigger.allowsEdgeHover else { return }
        guard NSMouseInRect(point, screen.frame, false) else {
            // Pointer left this screen entirely → hide if shown.
            if isRevealed { scheduleHide() }
            return
        }
        if isRevealed {
            // Hide once the pointer leaves the revealed dock (plus a little slop).
            if !NSMouseInRect(point, revealedFrame().insetBy(dx: -12, dy: -12), false) {
                scheduleHide()
            } else {
                hideWork?.cancel(); hideWork = nil
            }
        } else if pointerInRevealZone(point) {
            scheduleReveal()
        }
    }

    private func scheduleReveal() {
        guard revealWork == nil else { return }
        let work = DispatchWorkItem { [weak self] in self?.revealWork = nil; self?.reveal() }
        revealWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + preferences.revealDelayMs / 1000.0, execute: work)
    }

    private func scheduleHide() {
        guard hideWork == nil else { return }
        let work = DispatchWorkItem { [weak self] in self?.hideWork = nil; self?.hide() }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + preferences.hideDelayMs / 1000.0, execute: work)
    }

    /// The thin band along the dock's edge (and over its along-extent) that triggers
    /// a reveal when the pointer enters it.
    private func pointerInRevealZone(_ point: NSPoint) -> Bool {
        let f = screen.frame
        let threshold: CGFloat = 3
        let revealed = revealedFrame()
        switch anchor.edge {
        case .bottom:
            return point.y <= f.minY + threshold && point.x >= revealed.minX && point.x <= revealed.maxX
        case .top:
            return point.y >= f.maxY - threshold && point.x >= revealed.minX && point.x <= revealed.maxX
        case .left:
            return point.x <= f.minX + threshold && point.y >= revealed.minY && point.y <= revealed.maxY
        case .right:
            return point.x >= f.maxX - threshold && point.y >= revealed.minY && point.y <= revealed.maxY
        }
    }

    // MARK: Frames

    private func contentSize() -> CGSize {
        let base = DockLayout.contentSize(tileCount: model.tiles.count,
                                          iconSize: CGFloat(preferences.iconSize),
                                          spacing: CGFloat(preferences.tileSpacing),
                                          padding: DockView.padding,
                                          edge: anchor.edge)
        // Headroom so magnified tiles aren't clipped by the window bounds.
        guard preferences.magnificationEnabled else { return base }
        let extra = (preferences.effectiveMagnification - 1) * CGFloat(preferences.iconSize)
        return anchor.edge.isHorizontal
            ? CGSize(width: base.width, height: base.height + extra)
            : CGSize(width: base.width + extra, height: base.height)
    }

    private func revealedFrame() -> CGRect {
        DockLayout.revealedFrame(anchor: anchor, contentSize: contentSize(), in: screen.visibleFrame)
    }

    private func hiddenFrame() -> CGRect {
        DockLayout.hiddenFrame(edge: anchor.edge, revealedFrame: revealedFrame(), in: screen.visibleFrame)
    }

    private func setFrame(_ frame: CGRect, animated: Bool) {
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        if animated && !reduceMotion && preferences.animationMs > 0 {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = preferences.animationMs / 1000.0
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().setFrame(frame, display: true)
            }
        } else {
            panel.setFrame(frame, display: true)
        }
    }
}
