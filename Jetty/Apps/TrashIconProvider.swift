import AppKit

/// The Trash tile's empty/full artwork (IDEA-5). See TRASH.md for the research.
///
/// What doesn't work and isn't tried here: the legacy named images
/// (`NSImage.trashFullName`/`trashEmptyName`) return nil on macOS 26, and
/// `NSWorkspace.icon(forFile: ~/.Trash)` returns the generic *folder* icon, not
/// the trash can. What does work: reading the exact resources Finder uses from
/// `CoreTypes.bundle` — world-readable, no permission required. If Apple ever
/// moves them, each state falls back independently to the SF Symbol pair.
enum TrashIconProvider {

    /// The Trash-can image for the given fullness. Never nil (SF Symbols are
    /// always available); prefers the genuine system artwork.
    static func icon(isFull: Bool) -> NSImage {
        isFull ? fullIcon : emptyIcon
    }

    private static let emptyIcon: NSImage = load("TrashIcon") ?? symbol("trash", description: "Empty Trash")
    private static let fullIcon: NSImage = load("FullTrashIcon") ?? symbol("trash.fill", description: "Full Trash")

    /// `/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/<name>.icns`,
    /// validated — a missing or unreadable resource yields nil, not a blank image.
    private static func load(_ resourceName: String) -> NSImage? {
        let path = "/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/\(resourceName).icns"
        guard let image = NSImage(contentsOfFile: path), image.isValid else { return nil }
        return image
    }

    private static func symbol(_ name: String, description: String) -> NSImage {
        // SF Symbols ship with the OS since 11, so this cannot fail; force-trying
        // here would be acceptable, but keep the codebase's no-force style.
        NSImage(systemSymbolName: name, accessibilityDescription: description) ?? NSImage()
    }
}
