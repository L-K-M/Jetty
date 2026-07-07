import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Manage the dock's pinned items: reorder, remove, and add apps / files / folders /
/// links and the built-in tiles (separator, clock, Trash, Jetty Menu). Running apps
/// that aren't pinned appear automatically and aren't listed here. See PLAN.md §7.
struct ItemsView: View {
    @ObservedObject var store: DockStore
    @State private var selection: Set<UUID> = []

    var body: some View {
        VStack(spacing: 0) {
            List(selection: $selection) {
                ForEach(store.items) { item in
                    row(item).tag(item.id)
                }
                .onMove { store.moveItem(fromOffsets: $0, toOffset: $1) }
                .onDelete { offsets in
                    // Resolve ids *before* mutating — deleting by index while the array
                    // shifts under us would remove the wrong rows on a multi-row delete.
                    let ids = offsets.compactMap { store.items.indices.contains($0) ? store.items[$0].id : nil }
                    ids.forEach { store.removeItem(id: $0) }
                }
            }
            // Make the ⌫ shortcut the footer promises actually work: with no List
            // selection there was nothing for the delete key to act on (F-L8).
            .onDeleteCommand {
                selection.forEach { store.removeItem(id: $0) }
                selection.removeAll()
            }

            Divider()

            HStack {
                Menu("Add") {
                    Button("Application…") { addApplication() }
                    Button("File or Folder…") { addFileOrFolder() }
                    Button("Link…") { addLink() }
                    Divider()
                    Button("Separator") { store.addItem(DockItem(kind: .separator)) }
                    Button("Clock") { store.addItem(DockItem(kind: .clock, displayName: "Clock")) }
                    Button("Jetty Menu") { store.addItem(DockItem(kind: .jettyMenu, displayName: "Jetty Menu")) }
                    Button("Running Apps") {
                        // Only one running-apps sentinel — a second would re-emit the whole
                        // running group with duplicate tile ids (F-M1).
                        guard !store.items.contains(where: { $0.kind == .runningApps }) else { return }
                        store.addItem(DockItem(kind: .runningApps, displayName: "Running Apps"))
                    }
                    Button("Trash") { store.addItem(DockItem(kind: .trash, displayName: "Trash")) }
                    Divider()
                    Menu("Info Widget") {
                        Button("Battery") { store.addItem(DockItem(kind: .battery, displayName: "Battery")) }
                        Button("System Monitor") { store.addItem(DockItem(kind: .systemMonitor, displayName: "System Monitor")) }
                        Button("World Clock") { store.addItem(DockItem(kind: .worldClock, displayName: "World Clock")) }
                        Button("Pomodoro") { store.addItem(DockItem(kind: .pomodoro, displayName: "Pomodoro")) }
                        Button("Weather") { store.addItem(DockItem(kind: .weather, displayName: "Weather")) }
                        Button("Now Playing") { store.addItem(DockItem(kind: .nowPlaying, displayName: "Now Playing")) }
                    }
                }
                .frame(width: 100)
                Spacer()
                Text("Drag to reorder · swipe or ⌫ to remove").font(.caption).foregroundStyle(.secondary)
            }
            .padding(10)
        }
    }

    private func row(_ item: DockItem) -> some View {
        HStack(spacing: 10) {
            icon(for: item).frame(width: 22, height: 22)
            Text(displayName(item))
            Spacer()
            Text(item.kind.rawValue).font(.caption).foregroundStyle(.secondary)
        }
        .contextMenu {
            if item.kind != .separator && item.kind != .runningApps {
                Button("Rename…") { renameItem(item) }
                if item.kind != .trash {
                    Button("Set Custom Icon…") { setCustomIcon(item) }
                }
                if item.kind != .trash && item.customIconPath != nil {
                    Button("Clear Custom Icon") { store.setCustomIconPath(nil, id: item.id) }
                }
            }
            if item.kind == .folder {
                Menu("Stack Style") {
                    ForEach(FolderStackStyle.allCases) { style in
                        Button {
                            store.setFolderDisplay(style, id: item.id)
                        } label: {
                            Label(style.rawValue.capitalized,
                                  systemImage: (item.folderDisplay ?? .grid) == style ? "checkmark" : "")
                        }
                    }
                }
            }
            Button("Remove", role: .destructive) { store.removeItem(id: item.id) }
        }
    }

    /// Picks an image file to use as a pinned item's icon (MF-7).
    private func setCustomIcon(_ item: DockItem) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        store.setCustomIconPath(url.path, id: item.id)
    }

    /// Prompts for a new display name for a pinned item (MF-7).
    private func renameItem(_ item: DockItem) {
        let alert = NSAlert()
        alert.messageText = "Rename"
        alert.informativeText = "Enter a new name for this dock item."
        alert.addButton(withTitle: "Rename")
        alert.addButton(withTitle: "Cancel")

        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        field.stringValue = displayName(item)
        alert.accessoryView = field
        alert.window.initialFirstResponder = field

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let name = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        store.rename(id: item.id, to: name)
    }

    @ViewBuilder
    private func icon(for item: DockItem) -> some View {
        if item.kind != .trash, let path = item.customIconPath, let image = NSImage(contentsOfFile: path) {
            Image(nsImage: image).resizable().scaledToFit()
        } else {
            defaultIcon(for: item)
        }
    }

    @ViewBuilder
    private func defaultIcon(for item: DockItem) -> some View {
        switch item.kind {
        case .separator: Image(systemName: "minus")
        case .clock: Image(systemName: "clock")
        case .jettyMenu: Image(systemName: "square.grid.2x2.fill")
        case .trash: Image(systemName: "trash")
        case .url: Image(systemName: "globe")
        case .runningApps: Image(systemName: "circle.grid.2x2")
        case .battery: Image(systemName: "battery.100")
        case .systemMonitor: Image(systemName: "gauge.with.dots.needle.50percent")
        case .worldClock: Image(systemName: "globe.americas")
        case .pomodoro: Image(systemName: "timer")
        case .weather: Image(systemName: "cloud.sun")
        case .nowPlaying: Image(systemName: "music.note")
        default:
            if let url = item.url ?? item.bundleIdentifier.flatMap({ NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) }) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().scaledToFit()
            } else {
                Image(systemName: "questionmark.app.dashed")
            }
        }
    }

    private func displayName(_ item: DockItem) -> String {
        if !item.displayName.isEmpty { return item.displayName }
        switch item.kind {
        case .separator: return "Separator"
        default: return item.url?.deletingPathExtension().lastPathComponent ?? item.kind.rawValue
        }
    }

    private func addApplication() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        var duplicateIDs: [UUID] = []
        var addedAny = false
        for url in panel.urls {
            var item = DockItem.application(at: url)
            // Skip an app already pinned (by bundle id) so we don't mint a duplicate
            // tile id for the same app (F-M1).
            if let bid = item.bundleIdentifier,
               let existing = store.items.first(where: { $0.kind == .application && $0.bundleIdentifier == bid }) {
                duplicateIDs.append(existing.id)
                continue
            }
            item.bookmark = BookmarkResolver.bookmark(for: url)
            store.addItem(item)
            addedAny = true
        }
        // A silently skipped duplicate made Add look broken (FAB-U5). When *everything*
        // picked was already pinned, highlight the existing rows as the feedback.
        if !addedAny && !duplicateIDs.isEmpty {
            selection = Set(duplicateIDs)
        }
    }

    private func addFileOrFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            var item = DockItem.fromFileURL(url)
            item.bookmark = BookmarkResolver.bookmark(for: url)
            store.addItem(item)
        }
    }

    /// Prompts for a web address and pins it as a `.url` tile (clicking it opens the
    /// link in the default browser). A missing scheme defaults to `https://`.
    private func addLink() {
        let alert = NSAlert()
        alert.messageText = "Add a Link"
        alert.informativeText = "Enter a web address to pin as a dock tile."
        alert.addButton(withTitle: "Add")
        alert.addButton(withTitle: "Cancel")

        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
        field.placeholderString = "https://example.com"
        alert.accessoryView = field
        alert.window.initialFirstResponder = field

        guard alert.runModal() == .alertFirstButtonReturn else { return }

        guard let url = ItemsView.normalizedLinkURL(from: field.stringValue) else { return }
        store.addItem(DockItem.fromLink(url))
    }

    /// Normalizes user-typed link text into a URL, prepending `https://` when the text
    /// has no real scheme. Detecting the scheme (not just "://") keeps non-hierarchical
    /// links like mailto:/tel: intact instead of mangling them to "https://mailto:…"
    /// (H18) — but `host:port` shapes like `localhost:3000` also match the scheme
    /// grammar, so a scheme only counts when it's followed by `//` or is a known
    /// non-hierarchical scheme (FAB-B14). Pure and static so it's unit-testable.
    static func normalizedLinkURL(from raw: String) -> URL? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }

        // Non-hierarchical schemes carry no "//" after the colon. Keep this list small:
        // anything else typed with a bare colon is far more likely host:port than an
        // exotic scheme, and https:// is the safer default for a dock tile.
        let nonHierarchicalSchemes: Set<String> = [
            "mailto", "tel", "sms", "facetime", "x-apple.systempreferences",
        ]

        var hasScheme = false
        if let match = text.range(of: #"^[a-zA-Z][a-zA-Z0-9+.\-]*:"#, options: .regularExpression) {
            let scheme = String(text[text.startIndex..<text.index(before: match.upperBound)]).lowercased()
            let rest = text[match.upperBound...]
            // `localhost:3000` / `example.com:8080` reach here with all-digit `rest`
            // (a port, not a scheme body) and fall through to the https:// prepend.
            hasScheme = rest.hasPrefix("//") || nonHierarchicalSchemes.contains(scheme)
        }

        let normalized = hasScheme ? text : "https://\(text)"
        guard let url = URL(string: normalized), url.scheme != nil else { return nil }
        return url
    }
}
