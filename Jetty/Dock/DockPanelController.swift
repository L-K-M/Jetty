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
final class DockPanelController {

    let displayUUID: String
    private let model: DockModel
    private let preferences: Preferences
    private let panel: NSPanel
    private let hostingView: DockHostingView
    /// A plain layer-backed view we own, between the window and the SwiftUI host.
    /// Reveal/hide animates *this* layer's `transform`, never the window frame.
    private let slideView: NSView

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

        hostingView = DockHostingView(rootView: DockView(model: model, preferences: preferences, anchor: anchor))
        slideView = NSView(frame: NSRect(x: 0, y: 0, width: 200, height: 80))

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
        // Layer-back the whole stack and clip to the window so the slid-away content
        // is simply masked off (no visible overdraw outside the panel bounds).
        container.wantsLayer = true
        container.layer?.masksToBounds = true

        // The window NEVER moves. Reveal/hide animates only `slideView.layer.transform`
        // — a pure GPU composite of content that stays logically on-screen, so its
        // backing is never discarded and SwiftUI is never re-laid-out mid-slide. That
        // off-screen window-frame animation was the source of the reveal stutter and
        // the "stuck half-revealed" hitch (perf).
        slideView.frame = container.bounds
        slideView.autoresizingMask = [.width, .height]
        slideView.translatesAutoresizingMaskIntoConstraints = true
        slideView.wantsLayer = true

        hostingView.translatesAutoresizingMaskIntoConstraints = true
        hostingView.autoresizingMask = [.width, .height]
        hostingView.wantsLayer = true
        hostingView.frame = slideView.bounds
        slideView.addSubview(hostingView)
        container.addSubview(slideView)
        panel.contentView = container
        recomputeFrames()
    }

    // MARK: Configuration

    func update(screen: NSScreen, anchor: DockAnchor) {
        let edgeChanged = self.anchor.edge != anchor.edge
        self.screen = screen
        self.anchor = anchor
        // The SwiftUI content lays out along the anchor's edge, so refresh it when the
        // edge changes (per-display override / MF-1).
        if edgeChanged { hostingView.rootView = DockView(model: model, preferences: preferences, anchor: anchor) }
        recomputeFrames()
        layoutForCurrentState()
    }

    /// Re-parks the panel at the revealed frame and re-applies the current
    /// revealed/hidden content offset (call after the tile set or appearance changes).
    func layoutForCurrentState() {
        recomputeFrames()
        applyRevealState(animated: false)
        if !panel.isVisible { panel.orderFrontRegardless() }
    }

    func showInitial() {
        recomputeFrames()
        isRevealed = !preferences.autoHide
        applyRevealState(animated: false)
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
        applyRevealState(animated: animated)
    }

    func hide(animated: Bool = true) {
        revealWork?.cancel(); revealWork = nil
        guard isRevealed, preferences.autoHide else { return }
        hideIgnoringAutoHide(animated: animated)
    }

    func toggle() {
        if isRevealed { hideIgnoringAutoHide() } else { reveal() }
    }

    private func hideIgnoringAutoHide(animated: Bool = true) {
        revealWork?.cancel(); revealWork = nil
        guard isRevealed else { return }
        isRevealed = false
        applyRevealState(animated: animated)
    }

    /// Pointer moved (global coordinates) — decide whether to reveal or hide.
    func handleMouseMoved(to point: NSPoint) {
        guard preferences.autoHide, preferences.revealTrigger.allowsEdgeHover else { return }
        guard NSMouseInRect(point, screen.frame, false) else {
            // Pointer left this screen entirely → hide if shown.
            cancelScheduledReveal()
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
            // Slamming the pointer to the physical screen edge over the dock is
            // unambiguous intent — reveal immediately, bypassing the hover delay. A
            // mere near-edge hover still uses the short delay (avoids accidental pops).
            if pointerAtHardEdge(point) {
                revealWork?.cancel(); revealWork = nil
                reveal()
            } else {
                scheduleReveal()
            }
        } else {
            cancelScheduledReveal()
        }
    }

    private func cancelScheduledReveal() {
        revealWork?.cancel()
        revealWork = nil
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
        // Trigger against visibleFrame, not screen.frame, so a top dock reveals at
        // the menu-bar boundary (where its peek actually sits) rather than only when
        // the pointer is shoved up into the menu bar (BUG-5). The band and the
        // along-extent are widened a touch for easier targeting (perf/feel).
        let vf = screen.visibleFrame
        let threshold: CGFloat = 8
        let m: CGFloat = 16   // along-extent margin so near-misses still trigger
        let r = revealedFrame()
        switch anchor.edge {
        case .bottom:
            return point.y <= vf.minY + threshold && point.x >= r.minX - m && point.x <= r.maxX + m
        case .top:
            return point.y >= vf.maxY - threshold && point.x >= r.minX - m && point.x <= r.maxX + m
        case .left:
            return point.x <= vf.minX + threshold && point.y >= r.minY - m && point.y <= r.maxY + m
        case .right:
            return point.x >= vf.maxX - threshold && point.y >= r.minY - m && point.y <= r.maxY + m
        }
    }

    /// Whether the pointer is pinned at the *physical* screen edge over the dock's
    /// extent — an unambiguous reveal intent that bypasses the hover delay.
    private func pointerAtHardEdge(_ point: NSPoint) -> Bool {
        let f = screen.frame
        let slop: CGFloat = 1.5
        let m: CGFloat = 16
        let r = revealedFrame()
        switch anchor.edge {
        case .bottom:
            return point.y <= f.minY + slop && point.x >= r.minX - m && point.x <= r.maxX + m
        case .top:
            return point.y >= f.maxY - slop && point.x >= r.minX - m && point.x <= r.maxX + m
        case .left:
            return point.x <= f.minX + slop && point.y >= r.minY - m && point.y <= r.maxY + m
        case .right:
            return point.x >= f.maxX - slop && point.y >= r.minY - m && point.y <= r.maxY + m
        }
    }

    // MARK: Frames

    private func contentSize() -> CGSize {
        let base = DockLayout.contentSize(tiles: model.tiles.map(\.kind),
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

    // Cached revealed frame so per-mouse-move hit-testing is pure rect math (no
    // contentSize recompute on every pointer event). The panel is *always* parked
    // here — hidden vs. revealed is a content-layer transform, not a window move.
    // Refreshed by `recomputeFrames()` whenever the tiles, appearance, screen, or
    // anchor change.
    private var revealedFrameValue: CGRect = .zero

    private func recomputeFrames() {
        let content = contentSize()
        revealedFrameValue = DockLayout.revealedFrame(anchor: anchor, contentSize: content, in: screen.visibleFrame)
    }

    private func revealedFrame() -> CGRect { revealedFrameValue }

    /// The content-layer translation that parks the dock just off its screen edge.
    /// Geometry is the layer-backed (non-flipped) view space: +y is up, +x is right.
    private func hiddenTransform() -> CATransform3D {
        let w = revealedFrameValue.width
        let h = revealedFrameValue.height
        switch anchor.edge {
        case .bottom: return CATransform3DMakeTranslation(0, -h, 0)
        case .top:    return CATransform3DMakeTranslation(0,  h, 0)
        case .left:   return CATransform3DMakeTranslation(-w, 0, 0)
        case .right:  return CATransform3DMakeTranslation( w, 0, 0)
        }
    }

    /// Parks the (always on-screen) panel at the revealed frame and slides the dock
    /// content in/out by animating only the content layer's transform — pure GPU
    /// compositing, so reveal never re-renders the SwiftUI tree or the window backing.
    private func applyRevealState(animated: Bool) {
        if panel.frame != revealedFrameValue {
            panel.setFrame(revealedFrameValue, display: false)
        }
        // Click-through while hidden so the parked (transparent) panel never eats
        // events meant for whatever sits under the dock strip.
        panel.ignoresMouseEvents = !isRevealed
        guard let layer = slideView.layer else { return }
        let target = isRevealed ? CATransform3DIdentity : hiddenTransform()
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        if animated && !reduceMotion && preferences.animationMs > 0 {
            let from = layer.presentation()?.transform ?? layer.transform
            let anim = CABasicAnimation(keyPath: "transform")
            anim.fromValue = NSValue(caTransform3D: from)
            anim.toValue = NSValue(caTransform3D: target)
            anim.duration = preferences.animationMs / 1000.0
            anim.timingFunction = CAMediaTimingFunction(name: .easeOut)
            layer.add(anim, forKey: "revealSlide")
            layer.transform = target
        } else if layer.animation(forKey: "revealSlide") != nil,
                  CATransform3DEqualToTransform(layer.transform, target) {
            // A slide is already converging on this exact target (e.g. a tile-set or
            // appearance refresh landing mid-reveal) — let it finish rather than
            // snapping the content (which would reintroduce a visible hitch).
        } else {
            layer.removeAnimation(forKey: "revealSlide")
            layer.transform = target
        }
        panel.invalidateShadow()
    }
}
