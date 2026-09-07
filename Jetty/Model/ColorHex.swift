import AppKit
import SwiftUI

// The hex format itself lives in `RGBA8` — pure, portable, and unit-tested on both
// platforms, because it is a storage format every build has to agree on. What is left
// here is the part that genuinely needs a colour framework: converting to and from a
// live `NSColor`. See `docs/linux-port-plan.md` §JP-04.

// MARK: - NSColor hex support

extension NSColor {
    /// Parses `#RRGGBB`, `#RRGGBBAA`, or the CSS shorthands `#RGB`/`#RGBA`
    /// (the leading `#` is optional).
    convenience init?(hex: String) {
        guard let c = RGBA8(hex: hex) else { return nil }
        self.init(srgbRed: CGFloat(c.red) / 255,
                  green: CGFloat(c.green) / 255,
                  blue: CGFloat(c.blue) / 255,
                  alpha: CGFloat(c.alpha) / 255)
    }

    /// `#RRGGBB` (fully opaque) or `#RRGGBBAA` (translucent) in the sRGB color space.
    var hexString: String {
        guard let c = usingColorSpace(.sRGB) else { return "#000000" }
        // `RGBA8.init(clampingRed:...)` carries the clamp: wide-gamut sources can report
        // components outside 0...1 even after `.sRGB` (H19).
        return RGBA8(clampingRed: Double(c.redComponent),
                     green: Double(c.greenComponent),
                     blue: Double(c.blueComponent),
                     alpha: Double(c.alphaComponent)).hexString
    }
}

// MARK: - SwiftUI Color bridging

extension Color {
    /// Creates a `Color` from a `#RRGGBB[AA]` (or `#RGB[A]` shorthand) string,
    /// falling back to clear.
    init(hexString: String) {
        self = Color(nsColor: NSColor(hex: hexString) ?? .clear)
    }

    /// The hex string for this color (best-effort via `NSColor`).
    var hexString: String {
        NSColor(self).hexString
    }
}
