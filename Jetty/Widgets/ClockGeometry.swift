import CoreGraphics
import Foundation

/// Pure geometry for the analog clock faces: hand angles from wall-clock
/// components, and polar→canvas point math. No SwiftUI, so it's unit-testable
/// like `ClockFormatter`. See PLAN.md §8.1.
enum ClockGeometry {

    struct HandAngles: Equatable {
        var hour: Double
        var minute: Double
        var second: Double
    }

    /// Hand angles in radians, measured clockwise from 12 o'clock. The minute
    /// hand sweeps continuously with the seconds and the hour hand with the
    /// minutes, so the dial never jumps.
    static func handAngles(hour: Int, minute: Int, second: Int) -> HandAngles {
        let s = Double(second)
        let m = Double(minute) + s / 60
        let h = Double(hour % 12) + m / 60
        return HandAngles(hour: h / 12 * 2 * .pi,
                          minute: m / 60 * 2 * .pi,
                          second: s / 60 * 2 * .pi)
    }

    /// The point `distance` from `center` at `angle` (0 = straight up, growing
    /// clockwise) in a y-down canvas coordinate space.
    ///
    /// The results are annotated as Double so `sin`/`cos` resolve unambiguously —
    /// mixing the Double `angle` with the CGFloat `distance` lets the Xcode 26
    /// type-checker see both the Double and CGFloat overloads as equally valid
    /// ("ambiguous use of 'sin'"), which broke the build.
    static func point(center: CGPoint, angle: Double, distance: CGFloat) -> CGPoint {
        let dx: Double = sin(angle)
        let dy: Double = cos(angle)
        return CGPoint(x: center.x + CGFloat(dx) * distance, y: center.y - CGFloat(dy) * distance)
    }
}
