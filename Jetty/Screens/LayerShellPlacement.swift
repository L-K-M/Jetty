#if canImport(CoreGraphics)
import CoreGraphics
#else
import Foundation
#endif

/// A `DockLayout` frame expressed the way `zwlr_layer_shell_v1` accepts placement:
/// anchor edges, per-edge margins, and an exclusive zone. Pure and Equatable, so the
/// contract with the Wayland side is unit-tested here rather than only in a headless
/// compositor. See `docs/linux-port-plan.md` §JP-03 (this type) and §JP-24 (the
/// binding that consumes it).
///
/// Layer-shell does not take a rectangle. It takes an anchor and offsets *from* it,
/// and — this is the part that bites — `set_margin`'s own description says outright
/// that "setting this value for edges you are not anchored to has no effect". So a
/// margin and the anchor that gives it meaning are one decision, not two, and this
/// type keeps them together: everything a caller needs is derived here, in one place,
/// from one frame.
struct LayerShellPlacement: Equatable {

    /// `set_margin(top, right, bottom, left)`, in surface-local points. Only the
    /// entries whose edge appears in `anchorEdges` are meaningful; the rest are zero,
    /// which is both what the protocol ignores and what makes a stray non-zero value
    /// visible in a test rather than silently discarded on the wire.
    ///
    /// These are gaps between the frame's side and the same side of the bounds, so
    /// they carry no handedness: `top` is the distance below the top of the output
    /// whichever way the caller's y axis runs. The single deliberate y-flip lives at
    /// the toolkit boundary (JP-24), not here.
    struct Margins: Equatable {
        var top: Int32 = 0
        var right: Int32 = 0
        var bottom: Int32 = 0
        var left: Int32 = 0
    }

    /// The edges passed to `set_anchor`. Always exactly two orthogonal edges — the
    /// dock's own edge plus one along it — because the protocol resolves an orthogonal
    /// pair to "the intersection of the edges", i.e. a corner, and a corner plus two
    /// margins is the only anchor form that can express Jetty's centre-plus-offset
    /// placement. Anchoring the dock's edge alone would let the compositor centre the
    /// surface along it, discarding `alignment` and `offset` entirely.
    let anchorEdges: Set<DockEdge>

    let margins: Margins

    /// Always `LayerShellPlacement.exclusiveZone`. Present as a stored property so a
    /// caller destructures one value and cannot forget the request — and a `let` with
    /// a default, which drops it from the memberwise initialiser, so no producer can
    /// quietly hand out a placement that reserves space.
    let exclusiveZone: Int32 = LayerShellPlacement.exclusiveZone

    /// Reserve nothing. Jetty floats over content and auto-hides — `AGENTS.md`'s one
    /// load-bearing design decision — so a positive zone is out. Zero, not `-1`:
    /// `-1` asks not to be moved for other panels and to be extended to the raw output
    /// edge, which overlaps a Plasma panel or waybar instead of sitting clear of it.
    /// Zero reserves nothing *and* asks to be placed clear of everyone else's zone,
    /// which is the faithful analogue of the `NSScreen.visibleFrame` the macOS side
    /// already lays out against. Recorded in `docs/linux-port.md`.
    static let exclusiveZone: Int32 = 0
}

extension DockLayout {

    /// Expresses `frame` — a revealed or hidden frame from this file's own geometry,
    /// in the output's local coordinates — as layer-shell placement within `bounds`.
    ///
    /// `bounds` is the same rect the frame was laid out against, so the two agree by
    /// construction; JP-24 passes a per-output `CGRect(0, 0, usable.width,
    /// usable.height)` to both.
    ///
    /// The along-edge anchor is always the low side (left for a horizontal dock, top
    /// for a vertical one) rather than the side the frame happens to sit nearer.
    /// Choosing by proximity would put a discontinuity in the middle of the screen,
    /// where a one-point drag flips the anchor and the margin jumps the width of the
    /// output; a fixed side is stable, and Jetty recomputes placement on every output
    /// change anyway.
    ///
    /// Margins may be **negative**, deliberately: `hiddenFrame` slides the dock off
    /// its edge, and a negative margin is how that reaches the compositor. Clamping
    /// them at zero here would pin the hidden dock to the screen edge, permanently
    /// visible.
    static func layerShellPlacement(frame: CGRect, in bounds: CGRect,
                                    edge: DockEdge) -> LayerShellPlacement {
        // Gaps between each side of the frame and the same side of the bounds.
        let left = frame.minX - bounds.minX
        let right = bounds.maxX - frame.maxX
        let bottom = frame.minY - bounds.minY
        let top = bounds.maxY - frame.maxY

        var margins = LayerShellPlacement.Margins()
        let anchors: Set<DockEdge>
        switch edge {
        case .bottom:
            anchors = [.bottom, .left]
            margins.bottom = wireMargin(bottom)
            margins.left = wireMargin(left)
        case .top:
            anchors = [.top, .left]
            margins.top = wireMargin(top)
            margins.left = wireMargin(left)
        case .left:
            anchors = [.left, .top]
            margins.left = wireMargin(left)
            margins.top = wireMargin(top)
        case .right:
            anchors = [.right, .top]
            margins.right = wireMargin(right)
            margins.top = wireMargin(top)
        }
        return LayerShellPlacement(anchorEdges: anchors, margins: margins)
    }

    /// Rounds a point distance to the `int` `set_margin` takes, saturating instead of
    /// trapping. A `CGFloat` that overflows `Int32` can only come from a corrupt frame,
    /// and a dock placed at the far edge of the world is a better outcome than an
    /// arithmetic crash inside the compositor callback.
    private static func wireMargin(_ value: CGFloat) -> Int32 {
        guard value.isFinite else { return 0 }
        let rounded = value.rounded()
        if rounded <= CGFloat(Int32.min) { return .min }
        if rounded >= CGFloat(Int32.max) { return .max }
        return Int32(rounded)
    }
}
