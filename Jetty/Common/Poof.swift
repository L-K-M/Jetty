import AppKit

/// The classic Dock "poof" — a puff of cloud plus the system sound — played when a
/// tile is removed (drag-out or the context menu). Wraps `NSAnimationEffect.poof`,
/// which renders at a screen point in Cocoa (y-up) coordinates. See ND-5.
enum Poof {
    static func play(at screenPoint: NSPoint, size: CGFloat = 64) {
        NSAnimationEffect.poof.show(centeredAt: screenPoint,
                                    size: NSSize(width: size, height: size),
                                    completionHandler: nil)
    }
}
