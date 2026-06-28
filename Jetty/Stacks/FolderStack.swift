import SwiftUI
import AppKit

/// One entry in a folder stack popover.
struct FolderEntry: Identifiable {
    let id: String          // the file-system path
    let url: URL
    let name: String
    let icon: NSImage
    let isDirectory: Bool
}

/// Pure helpers + content reading for the folder-stack popover (MF-2). The geometry
/// and ordering are pure (unit-tested); directory reading touches the filesystem and
/// is done off the main thread by `FolderStackModel` (ISSUE-4).
enum FolderStack {

    /// Directories first, then case-insensitive name order — the conventional Finder
    /// "name" sort with folders grouped. Pure, so it's unit-tested.
    static func orderedBefore(_ a: (name: String, isDirectory: Bool),
                              _ b: (name: String, isDirectory: Bool)) -> Bool {
        if a.isDirectory != b.isDirectory { return a.isDirectory && !b.isDirectory }
        return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
    }

    /// Reads a folder's immediate, non-hidden contents (capped), sorted for display.
    /// Call off the main thread — it hits the filesystem and loads icons.
    static func entries(of folder: URL, limit: Int = 128) -> [FolderEntry] {
        let keys: [URLResourceKey] = [.isDirectoryKey, .localizedNameKey]
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]) else { return [] }

        let mapped: [FolderEntry] = urls.map { url in
            let values = try? url.resourceValues(forKeys: Set(keys))
            let name = values?.localizedName ?? url.lastPathComponent
            let isDir = values?.isDirectory ?? false
            return FolderEntry(id: url.path, url: url, name: name,
                               icon: NSWorkspace.shared.icon(forFile: url.path), isDirectory: isDir)
        }
        return mapped
            .sorted { orderedBefore(($0.name, $0.isDirectory), ($1.name, $1.isDirectory)) }
            .prefix(limit)
            .map { $0 }
    }

    // MARK: Geometry (pure)

    static let maxPanelHeight: CGFloat = 520

    /// A fixed popover size per style — fixed (not per-count) so drilling into
    /// subfolders doesn't make the panel jump around; contents scroll inside.
    static func panelSize(style: FolderStackStyle) -> CGSize {
        switch style {
        case .grid: return CGSize(width: 392, height: 440)
        case .list: return CGSize(width: 300, height: 440)
        case .fan:  return CGSize(width: 320, height: 460)
        }
    }

    /// Panel size for a style + entry count (kept for unit tests / callers that want a
    /// content-fitted size).
    static func panelSize(style: FolderStackStyle, count: Int) -> CGSize {
        let n = max(count, 1)
        switch style {
        case .grid:
            let columns = min(5, max(1, Int(ceil(Double(n).squareRoot()))))
            let rows = Int(ceil(Double(n) / Double(columns)))
            let cell: CGFloat = 84
            return CGSize(width: CGFloat(columns) * cell + 24,
                          height: min(CGFloat(rows) * cell + 56, maxPanelHeight))
        case .list:
            return CGSize(width: 280, height: min(CGFloat(n) * 34 + 56, maxPanelHeight))
        case .fan:
            return CGSize(width: 300, height: min(CGFloat(n) * 56 + 56, maxPanelHeight))
        }
    }

    /// Top-left origin (Cocoa, y-up) for a stack of `size` opened near `point`, placed
    /// just *outside* the `dock` frame along `edge` (so it never overlaps the dock) and
    /// centred on the click along the dock axis, clamped inside `visibleFrame`.
    static func origin(for size: CGSize, near point: CGPoint, dock: CGRect, edge: DockEdge, in vf: CGRect) -> CGPoint {
        let margin: CGFloat = 12
        var x = point.x - size.width / 2     // centre on the click along a horizontal dock
        var y = point.y - size.height / 2    // centre on the click along a vertical dock
        switch edge {
        case .bottom: y = dock.maxY + margin
        case .top:    y = dock.minY - size.height - margin
        case .left:   x = dock.maxX + margin
        case .right:  x = dock.minX - size.width - margin
        }
        x = min(max(x, vf.minX + 8), vf.maxX - size.width - 8)
        y = min(max(y, vf.minY + 8), vf.maxY - size.height - 8)
        return CGPoint(x: x, y: y)
    }
}

/// Observable backing for the folder-stack popover: loads a folder's contents off the
/// main thread (so opening a large / cloud-backed folder never hitches the dock —
/// ISSUE-4) and supports drilling into subfolders with a back button.
final class FolderStackModel: ObservableObject {
    @Published private(set) var entries: [FolderEntry] = []
    @Published private(set) var isLoading = false
    @Published private(set) var title = ""
    @Published private(set) var canGoBack = false

    let style: FolderStackStyle

    private var path: [URL] = []
    private var loadToken = 0
    private let queue = DispatchQueue(label: "ch.lkmc.jetty.folderstack", qos: .userInitiated)

    init(style: FolderStackStyle) { self.style = style }

    var currentFolder: URL? { path.last }

    /// Drills into `folder` (also used for the initial open).
    func open(_ folder: URL) {
        path.append(folder)
        reload()
    }

    /// Goes back up one level, if possible.
    func goBack() {
        guard path.count > 1 else { return }
        path.removeLast()
        reload()
    }

    private func reload() {
        guard let folder = path.last else { return }
        title = folder.lastPathComponent
        canGoBack = path.count > 1
        isLoading = true
        entries = []
        loadToken += 1
        let token = loadToken
        queue.async { [weak self] in
            let result = FolderStack.entries(of: folder)
            DispatchQueue.main.async {
                guard let self, token == self.loadToken else { return }   // ignore stale loads
                self.entries = result
                self.isLoading = false
            }
        }
    }
}

/// The folder-stack popover content: a header (with a back button when drilled in),
/// a loading state, and the folder's contents as a grid, list, or cascading fan.
/// Clicking a subfolder drills in; clicking a file opens it. See MF-2.
struct FolderStackView: View {
    @ObservedObject var model: FolderStackModel
    @ObservedObject var preferences: Preferences
    var onSelect: (FolderEntry) -> Void
    var onBack: () -> Void
    var onOpenInFinder: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.5)
            Group {
                if model.isLoading {
                    ProgressView().controlSize(.small)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if model.entries.isEmpty {
                    Text("Empty folder").foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView { content.padding(10) }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            GlassBackground(material: preferences.material,
                            tint: preferences.tintColor,
                            gradientColor: preferences.gradientColor,
                            gradientAngle: preferences.gradientAngle,
                            opacity: max(preferences.backgroundOpacity, 0.85),
                            cornerRadius: 16)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var header: some View {
        HStack(spacing: 8) {
            if model.canGoBack {
                Button { onBack() } label: { Image(systemName: "chevron.backward") }
                    .buttonStyle(.plain).help("Back")
            }
            Image(systemName: "folder.fill").foregroundStyle(preferences.tintColor)
            Text(model.title).font(.headline).lineLimit(1)
            Spacer()
            Button { onOpenInFinder() } label: { Image(systemName: "arrow.up.forward.app") }
                .buttonStyle(.plain)
                .help("Open in Finder")
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
    }

    @ViewBuilder
    private var content: some View {
        switch model.style {
        case .grid: grid
        case .list: list
        case .fan:  fan
        }
    }

    private var grid: some View {
        let columns = Array(repeating: GridItem(.fixed(72), spacing: 6), count: 4)
        return LazyVGrid(columns: columns, spacing: 6) {
            ForEach(model.entries) { entry in
                Button { onSelect(entry) } label: {
                    VStack(spacing: 4) {
                        icon(entry, size: 40)
                        Text(entry.name).font(.caption2).lineLimit(1).truncationMode(.middle)
                    }
                    .frame(width: 72, height: 70)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var list: some View {
        VStack(spacing: 2) {
            ForEach(model.entries) { entry in
                Button { onSelect(entry) } label: {
                    HStack(spacing: 8) {
                        icon(entry, size: 20)
                        Text(entry.name).lineLimit(1)
                        Spacer()
                        if entry.isDirectory {
                            Image(systemName: "chevron.forward").font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal, 8).padding(.vertical, 5)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// A nostalgic cascade: larger icons stepped diagonally with a slight tilt.
    private var fan: some View {
        VStack(spacing: 4) {
            ForEach(Array(model.entries.enumerated()), id: \.element.id) { index, entry in
                Button { onSelect(entry) } label: {
                    HStack(spacing: 10) {
                        icon(entry, size: 34)
                            .rotationEffect(.degrees(Double(min(index, 6)) * 1.5 - 4))
                        Text(entry.name).lineLimit(1)
                        Spacer()
                    }
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .offset(x: CGFloat(min(index, 6)) * 4)
            }
        }
    }

    private func icon(_ entry: FolderEntry, size: CGFloat) -> some View {
        Image(nsImage: entry.icon).resizable().scaledToFit().frame(width: size, height: size)
    }
}
