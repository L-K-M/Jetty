// Foundation unconditionally, to declare what the file uses: `isValid` trims with
// `trimmingCharacters(in:)`. This one is legibility rather than a latent break — it
// compiles without the import (measured), because Swift finds *members* in any module
// loaded into the compilation and other files here import Foundation. Only top-level
// names are file-scoped, which is what makes it load-bearing in `HotkeyBinding`.
import Foundation
#if canImport(AppKit)
import AppKit
#endif

/// The configurable icon for the Jetty-Menu dock tile (an SF Symbol name). The
/// chooser offers a big curated set of attractive symbols, but accepts *any* SF
/// Symbol name leniently — an unknown name simply falls back to the default, so the
/// tile never renders blank.
enum JettyMenuGlyph {

    static let fallback = "square.grid.2x2.fill"

    /// A curated set of launcher-y / delightful SF Symbols (all available on macOS 13).
    static let options: [String] = [
        "square.grid.2x2.fill", "square.grid.3x3.fill", "circle.grid.2x2.fill",
        "circle.grid.3x3.fill", "circle.grid.cross.fill", "rectangle.grid.2x2.fill",
        "circle.hexagongrid.fill", "square.stack.3d.up.fill", "square.stack.fill",
        "rectangle.3.group.fill", "squares.below.rectangle", "square.grid.3x1.below.line.grid.1x2",
        "sparkles", "wand.and.stars", "wand.and.rays", "star.fill", "star.circle.fill",
        "command", "command.circle.fill", "bolt.fill", "bolt.circle.fill",
        "paperplane.fill", "magnifyingglass", "magnifyingglass.circle.fill",
        "hexagon.fill", "seal.fill", "burst.fill", "flame.fill", "leaf.fill", "drop.fill",
        "moon.stars.fill", "sun.max.fill", "globe", "cube.fill", "diamond.fill",
        "app.fill", "circle.fill", "puzzlepiece.fill", "gamecontroller.fill",
        "paintpalette.fill", "lightbulb.fill", "atom", "theatermasks.fill",
        "gift.fill", "crown.fill", "heart.fill", "pawprint.fill", "bonjour",
    ]

    /// Whether `name` is a real SF Symbol (so we can offer only renderable choices and
    /// validate free-form input).
    static func isValid(_ name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        #if canImport(AppKit)
        return NSImage(systemSymbolName: trimmed, accessibilityDescription: nil) != nil
        #else
        // SF Symbols are Apple's catalogue, so off Darwin there is no system to ask.
        // Fall back to the curated list rather than accepting anything: this type's
        // contract is that an unknown name resolves to `fallback` so the tile never
        // renders blank, and `return true` would break that — `resolved` would hand a
        // Linux renderer a name it cannot draw. Narrower than the Darwin check (a real
        // symbol outside `options` is rejected here), which is the safe direction.
        return options.contains(trimmed)
        #endif
    }

    /// The symbol to actually render: the configured one if valid, else the fallback.
    static func resolved(_ name: String) -> String {
        isValid(name) ? name.trimmingCharacters(in: .whitespacesAndNewlines) : fallback
    }

    /// The curated options that actually resolve on this OS (so the picker never shows
    /// a blank cell if a name is unavailable on an older system). Computed once —
    /// symbol availability can't change mid-process, and the old computed property
    /// re-validated ~47 symbols (an `NSImage` alloc each) on every Settings render,
    /// including every keystroke in the custom-symbol field (F-P5).
    static let availableOptions: [String] = options.filter(isValid)
}
