import SwiftUI
import AppKit

/// The dock / Jetty-Menu background material.
///
/// On **macOS 26 (Tahoe)** this renders genuine **Liquid Glass** via SwiftUI's
/// public `.glassEffect`, so Jetty matches the system look (and honors the user's
/// Clear/Tinted + Reduce-Transparency settings, which the system applies to the
/// effect automatically). On macOS 13–15 — or when the material is `solid` /
/// `gradient`, or the user has Reduce Transparency on — it falls back to a rounded
/// `NSVisualEffectView` blur (or a flat fill / gradient) so the app still looks
/// right on older systems. See PLAN.md §9.
struct GlassBackground: View {
    var material: DockMaterial
    var tint: Color
    var gradientColor: Color
    var gradientAngle: Double
    var opacity: Double
    var cornerRadius: CGFloat

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        Group {
            switch material {
            case .liquidGlass, .glassClear, .glassTinted:
                glass(in: shape)
            case .solid:
                shape.fill(tint.opacity(opacity))
            case .gradient:
                shape.fill(
                    LinearGradient(
                        colors: [tint.opacity(opacity), gradientColor.opacity(opacity)],
                        startPoint: gradientStart,
                        endPoint: gradientEnd
                    )
                )
            }
        }
    }

    @ViewBuilder
    private func glass(in shape: RoundedRectangle) -> some View {
        if #available(macOS 26.0, *), !reduceTransparency {
            // Public Liquid Glass. `.clear` for the see-through variant; `.regular`
            // tinted for the tinted/standard variants. The dock is a floating
            // control layer — the textbook use case Apple documents for glass.
            let glass: Glass = {
                switch material {
                case .glassClear: return .clear
                case .glassTinted: return .regular.tint(tint.opacity(max(0.0, min(opacity, 1.0))))
                default: return .regular
                }
            }()
            Color.clear.glassEffect(glass, in: shape)
        } else {
            // Fallback for macOS 13–15 (or Reduce Transparency): a blurred panel
            // with a faint tint wash, clipped to the same rounded shape.
            ZStack {
                VisualEffectBlur(material: .hudWindow, blendingMode: .behindWindow)
                if material == .glassTinted {
                    tint.opacity(min(opacity, 0.5))
                }
            }
            .clipShape(shape)
        }
    }

    private var reduceTransparency: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
    }

    // 0° = top→bottom, increasing counterclockwise on screen — 90° runs left→right
    // (matches `AngleDial`; y grows downward so (sin, cos) puts 0° at the bottom).
    private var gradientStart: UnitPoint {
        let r = gradientAngle * .pi / 180
        return UnitPoint(x: 0.5 - sin(r) / 2, y: 0.5 - cos(r) / 2)
    }
    private var gradientEnd: UnitPoint {
        let r = gradientAngle * .pi / 180
        return UnitPoint(x: 0.5 + sin(r) / 2, y: 0.5 + cos(r) / 2)
    }
}
