import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Manage the dock's pinned items: reorder, remove, and add apps / files / folders /
/// links and the built-in tiles (separator, clock, Trash, Jetty Menu). Running apps
/// that aren't pinned appear automatically and aren't listed here. See PLAN.md §7.
struct ItemsView: View {
    @ObservedObject var store: DockStore

    var body: some View {
        VStack(spacing: 0) {
            List {
                ForEach(store.items) { item in
                    row(item)
                }
                .onMove { store.moveItem(fromOffsets: $0, toOffset: $1) }
                .onDelete { offsets in
                    for index in offsets where store.items.indices.contains(index) {
                        store.removeItem(id: store.items[index].id)
                    }
                }
            }

            Divider()

            HStack {
                Menu("Add") {
                    Button("Application…") { addApplication() }
                    Button("File or Folder…") { addFileOrFolder() }
                    Divider()
                    Button("Separator") { store.addItem(DockItem(kind: .separator)) }
                    Button("Clock") { store.addItem(DockItem(kind: .clock, displayName: "Clock")) }
                    Button("Jetty Menu") { store.addItem(DockItem(kind: .jettyMenu, displayName: "Jetty Menu")) }
                    Button("Trash") { store.addItem(DockItem(kind: .trash, displayName: "Trash")) }
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
    }

    @ViewBuilder
    private func icon(for item: DockItem) -> some View {
        switch item.kind {
        case .separator: Image(systemName: "minus")
        case .clock: Image(systemName: "clock")
        case .jettyMenu: Image(systemName: "square.grid.2x2.fill")
        case .trash: Image(systemName: "trash")
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
        for url in panel.urls {
            var item = DockItem.application(at: url)
            item.bookmark = BookmarkResolver.bookmark(for: url)
            store.addItem(item)
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
}
