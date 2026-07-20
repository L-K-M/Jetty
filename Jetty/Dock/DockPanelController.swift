import AppKit
import SwiftUI
import QuartzCore

/// An `NSHostingView` that accepts the first mouse click even when its window is
/// not key, so a click on the (background-app) dock registers immediately.
private final class DockHostingView: NSHostingView<DockView> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// A thin, transparent edge window's content view that catches a *file drag* aimed
/// at an auto-hidden dock: entering it reveals the dock, and dropping on it pins the
/// files. This exists because a Finder drag emits no `mouseMoved` events (so the
/// edge-hover monitor can't reveal mid-drag) and the parked dock panel is
/// click-through while hidden (so it isn't itself a drag destination). See PLAN.md §4.
private final class DragRevealSensorView: NSView {
    var onDragEnter: (() -> Void)?
    var onDropURLs: (([URL]) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([.fileURL])
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        onDragEnter?()
        return .copy
    }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation { .copy }
    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool { true }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let urls = sender.draggingPasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        guard !urls.isEmpty else { return false }
        onDropURLs?(urls)
        return true
    }
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
    private var interactionHeld = false

    /// A thin edge window that catches file drags while the dock is auto-hidden
    /// (present only when auto-hide + edge-hover are on). See `DragRevealSensorView`.
    private var sensorPanel: NSPanel?
    /// Pins file/folder URLs dropped onto the edge sensor (wired by the controller).
    var onDropToPin: (([URL]) -> Void)?

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
        layoutForCurrentState()
    }

    /// Re-parks the panel at the revealed frame and re-applies the current
    /// revealed/hidden content offset (call after the tile set or appearance changes).
    func layoutForCurrentState() {
        recomputeFrames()
        applyRevealState(animated: false)
        updateDragSensor()
        if !panel.isVisible { panel.orderFrontRegardless() }
    }

    func showInitial() {
        recomputeFrames()
        isRevealed = !preferences.autoHide
        applyRevealState(animated: false)
        updateDragSensor()
        panel.orderFrontRegardless()
    }

    func close() {
        revealWork?.cancel(); hideWork?.cancel()
        sensorPanel?.orderOut(nil); sensorPanel = nil
        panel.orderOut(nil)
    }

    // MARK: Reveal / hide

    /// Fired whenever the dock reveals, so state that must never be staler than the
    /// user's last look at the dock (the Trash fullness resolution — TRASH.md) can
    /// refresh on the one moment it matters.
    var onReveal: (() -> Void)?

    func reveal(animated: Bool = true) {
        hideWork?.cancel(); hideWork = nil
        guard !isRevealed else { return }
        isRevealed = true
        applyRevealState(animated: animated)
        onReveal?()
    }

    func hide(animated: Bool = true) {
        revealWork?.cancel(); revealWork = nil
        guard isRevealed, preferences.autoHide else { return }
        hideIgnoringAutoHide(animated: animated)
    }

    func toggle() {
        if isRevealed { hideIgnoringAutoHide() } else { reveal() }
    }

    /// Keeps an auto-hidden dock visible while a menu tracks outside its window.
    func setInteractionHeld(_ held: Bool) {
        interactionHeld = held
        if held {
            hideWork?.cancel()
            hideWork = nil
        } else {
            handleMouseMoved(to: NSEvent.mouseLocation)
        }
    }

    /// Force-hide regardless of the auto-hide setting — lets the global toggle-all
    /// hotkey hide even a pinned, always-shown dock (M34).
    func hideForToggle() {
        // A deliberate hide must not be instantly undone by a pointer that happens to
        // be resting in the reveal zone (the system Dock's ⌥⌘D behavior): suppress
        // edge reveal until the pointer has left the zone at least once.
        suppressEdgeReveal = true
        hideIgnoringAutoHide()
    }

    /// Latched by `hideForToggle`; cleared by `handleMouseMoved` once the pointer is
    /// outside the reveal zone / dock frame.
    private var suppressEdgeReveal = false

    private func hideIgnoringAutoHide(animated: Bool = true) {
        revealWork?.cancel(); revealWork = nil
        guard isRevealed else { return }
        isRevealed = false
        applyRevealState(animated: animated)
    }

    /// Pointer moved (global coordinates) — decide whether to reveal or hide.
    func handleMouseMoved(to point: NSPoint) {
        if interactionHeld {
            hideWork?.cancel()
            hideWork = nil
            return
        }
        guard preferences.autoHide, preferences.revealTrigger.allowsEdgeHover else { return }
        if suppressEdgeReveal {
            // Stay hidden while the pointer lingers in the reveal zone or over the
            // (hidden) dock frame; re-arm edge reveal once it has clearly left.
            let stillInZone = pointerInRevealZone(point) || pointerAtHardEdge(point)
                || pointerInKeepArea(point)
                || pointerCrossedDockEdge(point, band: max(36, CGFloat(preferences.hideDistance)))
            guard !stillInZone else { return }
            suppressEdgeReveal = false
        }
        guard NSMouseInRect(point, screen.frame, false) else {
            // The pointer is off this screen. A dock on a display stacked directly against
            // another (e.g. this screen sits ABOVE another) lives on an *internal seam*:
            // there's no physical screen edge to pin the cursor, so it glides onto the
            // neighbouring display before any sample can land in the on-screen reveal band
            // — and the dock would never reveal there. Treat a sample that has just crossed
            // this screen's dock edge (within a band past the edge, over the dock's
            // along-extent) as an edge slam (BUG: one-screen bottom-edge reveal).
            //
            // The reveal band is generous (24pt) because, unlike a real screen edge, a seam
            // doesn't clamp the cursor — a fast slam can overshoot well past it between two
            // samples, so a tight band would still be missed. A wider keep-revealed band
            // (36pt, or the hide-distance preference when larger) gives hysteresis
            // (reveal ≤24, stay ≤36, hide beyond) so the dock can't flap while the
            // pointer lingers just past the seam.
            if isRevealed {
                if pointerCrossedDockEdge(point, band: max(36, CGFloat(preferences.hideDistance))) {
                    hideWork?.cancel(); hideWork = nil
                } else {
                    scheduleHide()
                }
            } else if pointerCrossedDockEdge(point, band: 24) {
                revealWork?.cancel(); revealWork = nil
                reveal()
            } else {
                // The pointer left this screen without crossing the dock edge (e.g. it
                // slid sideways onto a neighbour mid-dwell). Drop any queued reveal so the
                // dock doesn't "ghost fire" on a screen the pointer has already left (H11).
                cancelScheduledReveal()
            }
            return
        }
        if isRevealed {
            // Hide once the pointer moves more than the configured hide distance from
            // the revealed dock. The keep-revealed region also spans any inset gap to
            // the physical edge, where the hard-edge reveal would instantly re-fire.
            if pointerInKeepArea(point) {
                hideWork?.cancel(); hideWork = nil
            } else {
                scheduleHide()
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
        guard !interactionHeld, hideWork == nil else { return }
        let work = DispatchWorkItem { [weak self] in self?.hideWork = nil; self?.hide() }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + preferences.hideDelayMs / 1000.0, execute: work)
    }

    /// The region that keeps a revealed dock up: the **visible glass strip**
    /// (`revealedDockStripFrame`) grown by the configured hide distance, bridged
    /// across any inset gap to the physical screen edge. Measuring from
    /// `revealedFrame()` instead added the panel's transparent headroom (hover
    /// magnification, a zoomed clock face, floating labels) to every hide, so the
    /// pointer had to travel hide-distance *plus* that headroom before the dock
    /// would hide (BUG: hide distance ignored).
    private func keepRevealedRegion() -> CGRect {
        DockLayout.keepRevealedFrame(revealed: revealedDockStripFrame,
                                     screenFrame: screen.frame,
                                     edge: anchor.edge,
                                     slop: CGFloat(preferences.hideDistance))
    }

    /// `keepRevealedRegion` plus any pointer genuinely over dock content: hovering a
    /// magnified tile reaches into the panel's transparent headroom, past the resting
    /// strip + hide distance. Hit-test the view hierarchy rather than the panel's
    /// bounding box — the box alone would treat empty headroom as "on the dock" and
    /// re-inflate every hide by that headroom (the bug this fixes).
    private func pointerInKeepArea(_ point: NSPoint) -> Bool {
        if NSMouseInRect(point, keepRevealedRegion(), false) { return true }
        guard NSMouseInRect(point, revealedFrame(), false) else { return false }
        // Screen → window coords (the borderless panel's content view starts at the
        // window origin). While hidden the content is slid off and clipped, so this
        // correctly hit-tests nil.
        let local = panel.convertPoint(point, from: nil)
        return panel.contentView?.hitTest(local) != nil
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

    /// Whether the pointer is within `band` points just **past** this screen's dock edge,
    /// over the dock's along-extent. On a display stacked against another, the shared seam
    /// lets the cursor glide onto the neighbour before it can land in the on-screen reveal
    /// band; catching the crossing makes the dock reachable there. On a true screen
    /// boundary this region is off-desktop, so the cursor can never reach it and this never
    /// fires (no regression for the common, non-stacked layout).
    private func pointerCrossedDockEdge(_ point: NSPoint, band: CGFloat) -> Bool {
        DockLayout.pointerCrossedEdge(point, screenFrame: screen.frame, dockFrame: revealedFrame(),
                                      edge: anchor.edge, band: band, margin: 16)
    }

    // MARK: Frames

    private func contentSize() -> CGSize {
        let icon = CGFloat(preferences.iconSize)
        let kinds = model.tiles.map(\.kind)
        let clockFactor = DockLayout.clockTileWidthFactor(zoom: CGFloat(preferences.effectiveClockZoom),
                                                          face: preferences.clockFace)
        let base = DockLayout.contentSize(tiles: kinds,
                                          iconSize: icon,
                                          spacing: CGFloat(preferences.tileSpacing),
                                          padding: DockView.padding,
                                          edge: anchor.edge,
                                          clockWidthFactor: clockFactor)
        let magFactor = preferences.effectiveMagnification
        // Along the dock: magnified tiles grow about their centre, so the ends
        // need room for the *widest* tile (a zoomed clock, now-playing) — a
        // square-tile budget clipped those at the window ends (ISSUE-2).
        let widest = anchor.edge.isHorizontal
            ? DockLayout.widestTileFactor(kinds: kinds, clockWidthFactor: clockFactor) : 1
        let along = DockLayout.magnificationAlongExtra(iconSize: icon, magnification: magFactor,
                                                       widestFactor: widest)
        // Across the dock: the larger of plain magnification and the zoomed
        // clock face — which itself magnifies on hover, so the two compound.
        // Horizontal docks only; `ClockWidgetView` ignores the zoom elsewhere.
        var across = max(0, (magFactor - 1) * icon)
        if anchor.edge.isHorizontal, preferences.clockFace != .digital,
           kinds.contains(.clock) {
            across = max(across, DockLayout.clockZoomHeadroom(
                iconSize: icon, padding: DockView.padding,
                zoom: CGFloat(preferences.clockFaceZoom),
                magnification: magFactor))
        }
        // Hover labels float ~0.75 × icon toward screen center (DockTileView); budget
        // room for them or the clipped container shaves — and with magnification off,
        // entirely hides — the label (BUG: clipped labels).
        if preferences.showLabels {
            across = max(across, DockLayout.labelHeadroom(iconSize: icon))
        }
        guard along > 0 || across > 0 else { return base }
        return anchor.edge.isHorizontal
            ? CGSize(width: base.width + along, height: base.height + across)
            : CGSize(width: base.width + across, height: base.height + along)
    }

    // Cached revealed frame so per-mouse-move hit-testing is pure rect math (no
    // contentSize recompute on every pointer event). The panel is *always* parked
    // here — hidden vs. revealed is a content-layer transform, not a window move.
    // Refreshed by `recomputeFrames()` whenever the tiles, appearance, screen, or
    // anchor change.
    private var revealedFrameValue: CGRect = .zero

    private func recomputeFrames() {
        let content = contentSize()
        // Keep the visual panel at the pure anchor frame. Stretching it back to the
        // physical edge erased a positive inset on bottom/left/right and could draw
        // Jetty over a visible system Dock. The separate drag/reveal sensor still owns
        // hard-edge discovery without changing the dock's visible placement.
        revealedFrameValue = DockLayout.revealedFrame(
            anchor: anchor, contentSize: content, in: screen.visibleFrame)
    }

    private func revealedFrame() -> CGRect { revealedFrameValue }

    /// The visible glass strip's screen frame, excluding transparent magnification
    /// headroom. Hover popovers anchor to this so they sit just above/beside the dock,
    /// not above the invisible room reserved for enlarged icons.
    var revealedDockStripFrame: CGRect {
        let thickness = min(CGFloat(preferences.iconSize) + 2 * DockView.padding,
                            anchor.edge.isHorizontal ? revealedFrameValue.height : revealedFrameValue.width)
        switch anchor.edge {
        case .bottom:
            return CGRect(x: revealedFrameValue.minX, y: revealedFrameValue.minY,
                          width: revealedFrameValue.width, height: thickness)
        case .top:
            return CGRect(x: revealedFrameValue.minX, y: revealedFrameValue.maxY - thickness,
                          width: revealedFrameValue.width, height: thickness)
        case .left:
            return CGRect(x: revealedFrameValue.minX, y: revealedFrameValue.minY,
                          width: thickness, height: revealedFrameValue.height)
        case .right:
            return CGRect(x: revealedFrameValue.maxX - thickness, y: revealedFrameValue.minY,
                          width: thickness, height: revealedFrameValue.height)
        }
    }

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

    // MARK: Drag-reveal sensor

    /// Creates/positions (or tears down) the thin edge window that lets a Finder drag
    /// reveal and drop onto the dock while it's auto-hidden. Only present when auto-hide
    /// and edge-hover are both on; otherwise the visible dock handles drops directly.
    private func updateDragSensor() {
        guard preferences.autoHide, preferences.revealTrigger.allowsEdgeHover else {
            sensorPanel?.orderOut(nil); sensorPanel = nil
            return
        }
        let panel = sensorPanel ?? makeSensorPanel()
        sensorPanel = panel
        panel.setFrame(sensorFrame(), display: false)
        if !panel.isVisible { panel.orderFrontRegardless() }
    }

    private func makeSensorPanel() -> NSPanel {
        let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 10, height: 6),
                        styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        p.isFloatingPanel = true
        p.becomesKeyOnlyIfNeeded = true
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        // Just *below* the dock panel so a revealed (non-click-through) dock always wins
        // the drop, but still above ordinary app windows so the sensor catches the drag
        // when the dock is hidden (and click-through).
        p.level = NSWindow.Level(rawValue: NSWindow.Level.popUpMenu.rawValue - 1)
        p.isMovable = false
        p.isReleasedWhenClosed = false
        p.isRestorable = false
        p.hidesOnDeactivate = false
        p.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        let view = DragRevealSensorView(frame: .zero)
        view.onDragEnter = { [weak self] in self?.reveal() }
        view.onDropURLs = { [weak self] urls in self?.reveal(); self?.onDropToPin?(urls) }
        p.contentView = view
        return p
    }

    /// A thin band hugging the usable-area edge over the dock's along-extent. Uses
    /// `visibleFrame` (not the physical screen edge) so a top dock's sensor sits below
    /// the menu bar — matching where the dock actually reveals.
    private func sensorFrame() -> CGRect {
        let t: CGFloat = 6
        let vf = screen.visibleFrame
        let r = revealedFrameValue
        switch anchor.edge {
        case .bottom: return CGRect(x: r.minX, y: vf.minY, width: r.width, height: t)
        case .top:    return CGRect(x: r.minX, y: vf.maxY - t, width: r.width, height: t)
        case .left:   return CGRect(x: vf.minX, y: r.minY, width: t, height: r.height)
        case .right:  return CGRect(x: vf.maxX - t, y: r.minY, width: t, height: r.height)
        }
    }
}
