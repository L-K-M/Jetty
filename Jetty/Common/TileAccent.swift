import AppKit
import SwiftUI
import CoreImage

/// The per-tile accent color used for the hover/active glow (ND-8): the icon's
/// average color, saturation-boosted so it reads as an accent rather than mud, and
/// cached by tile id (icons are stable, so the sample is computed once).
enum TileAccent {

    private static var cache: [String: Color] = [:]

    static func color(for tile: DockTile) -> Color? {
        if let cached = cache[tile.id] { return cached }
        guard let icon = tile.icon, let ns = icon.jettyDominantColor() else { return nil }
        let color = Color(nsColor: ns)
        cache[tile.id] = color
        return color
    }
}

private extension NSImage {
    /// The image's average color, pushed toward a vivid accent. `nil` if it can't be
    /// rasterized (e.g. an empty image).
    func jettyDominantColor() -> NSColor? {
        guard let tiff = tiffRepresentation, let ci = CIImage(data: tiff) else { return nil }
        let extent = ci.extent
        guard extent.width > 0, extent.height > 0,
              let filter = CIFilter(name: "CIAreaAverage",
                                    parameters: [kCIInputImageKey: ci,
                                                 kCIInputExtentKey: CIVector(cgRect: extent)]),
              let output = filter.outputImage else { return nil }

        var pixel = [UInt8](repeating: 0, count: 4)
        let context = CIContext(options: [.workingColorSpace: NSNull()])
        context.render(output, toBitmap: &pixel, rowBytes: 4,
                       bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                       format: .RGBA8, colorSpace: nil)

        let base = NSColor(red: CGFloat(pixel[0]) / 255, green: CGFloat(pixel[1]) / 255,
                           blue: CGFloat(pixel[2]) / 255, alpha: 1)
        guard let rgb = base.usingColorSpace(.deviceRGB) else { return base }
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        rgb.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        return NSColor(hue: h, saturation: min(s * 1.5, 1), brightness: max(b, 0.65), alpha: a)
    }
}
