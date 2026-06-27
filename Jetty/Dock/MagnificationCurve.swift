import CoreGraphics
import Foundation

/// Pure math for the Dock-style hover **magnification**: a tile grows as the
/// pointer nears it and tapers back to 1× past an influence radius. No state, so
/// it's unit-tested. See PLAN.md §9.
enum MagnificationCurve {

    /// The scale for a tile whose center is `distance` points from the pointer
    /// (measured along the dock's axis).
    ///
    /// - `distance`: absolute along-edge distance from the pointer to the tile center.
    /// - `influence`: radius of effect; tiles farther than this stay at 1×.
    /// - `maxScale`: the peak scale, applied at `distance == 0`.
    ///
    /// Uses a cosine falloff so the bump is smooth (no kink at the edge of the
    /// influence radius). Monotonically decreasing in `distance` over `[0, influence]`.
    static func scale(distance: CGFloat, influence: CGFloat, maxScale: CGFloat) -> CGFloat {
        guard maxScale > 1, influence > 0 else { return 1 }
        let d = abs(distance)
        guard d < influence else { return 1 }
        let falloff = cos((d / influence) * (.pi / 2))   // 1 at d=0, 0 at d=influence
        return 1 + (maxScale - 1) * max(0, falloff)
    }
}
