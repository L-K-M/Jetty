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
/// and ordering are pure (unit-tested); directory reading touches the filesystem.
enum FolderStack {

    /// Directories first, then case-insensitive name order — the conventional Finder
    /// "name" sort with folders grouped. Pure, so it's unit-tested.
    static func orderedBefore(_ a: (name: String, isDirectory: Bool),
                              _ b: (name: String, isDirectory: Bool)) -> Bool {
        if a.isDirectory != b.isDirectory { return a.isDirectory && !b.isDirectory }
        return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
    }

    /// Reads a folder's immediate, non-hidden contents (capped), sorted for display.
    static func entries(of folder: URL, limit: Int = 64) -> [FolderEntry] {
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

    /// Panel size for a style + entry count.
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

    /// Top-left origin (Cocoa, y-up) for a stack of `size` opened near `point` on a
    /// dock anchored to `edge`, clamped inside `visibleFrame`.
    static func origin(for size: CGSize, near point: CGPoint, edge: DockEdge, in vf: CGRect) -> CGPoint {
        let margin: CGFloat = 14
        var x = point.x - size.width / 2
        var y = point.y - size.height / 2
        switch edge {
        case .bottom: y = point.y + margin
        case .top:    y = point.y - size.height - margin
        case .left:   x = point.x + margin
        case .right:  x = point.x - size.width - margin
        }
        x = min(max(x, vf.minX + 8), vf.maxX - size.width - 8)
        y = min(max(y, vf.minY + 8), vf.maxY - size.height - 8)
        return CGPoint(x: x, y: y)
    }
}

/// The folder-stack popover content: a header plus the folder's contents rendered as
/// a grid, a list, or a cascading fan. Clicking an entry opens it. See MF-2.
struct FolderStackView: View {
    let folderName: String
    let entries: [FolderEntry]
    let style: FolderStackStyle
    @ObservedObject var preferences: Preferences
    var onOpen: (URL) -> Void
    var onOpenFolder: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.5)
            if entries.isEmpty {
                Text("Empty folder").foregroundStyle(.secondary).padding(28)
            } else {
                ScrollView { content.padding(10) }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            GlassBackground(material: preferences.material,
                            tint: preferences.tintColor,
                            gradientColor: preferences.gradientColor,
                            gradientAngle: preferences.gradientAngle,
                            opacity: max(preferences.backgroundOpacity, 0.8),
                            cornerRadius: 16)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "folder.fill").foregroundStyle(preferences.tintColor)
            Text(folderName).font(.headline).lineLimit(1)
            Spacer()
            Button { onOpenFolder() } label: { Image(systemName: "arrow.up.forward.app") }
                .buttonStyle(.plain)
                .help("Open “\(folderName)” in Finder")
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
    }

    @ViewBuilder
    private var content: some View {
        switch style {
        case .grid: grid
        case .list: list
        case .fan:  fan
        }
    }

    private var grid: some View {
        let columns = Array(repeating: GridItem(.fixed(72), spacing: 6), count: gridColumnCount)
        return LazyVGrid(columns: columns, spacing: 6) {
            ForEach(entries) { entry in
                Button { onOpen(entry.url) } label: {
                    VStack(spacing: 4) {
                        Image(nsImage: entry.icon).resizable().scaledToFit().frame(width: 40, height: 40)
                        Text(entry.name).font(.caption2).lineLimit(1).truncationMode(.middle)
                    }
                    .frame(width: 72, height: 70)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var gridColumnCount: Int {
        min(5, max(1, Int(ceil(Double(max(entries.count, 1)).squareRoot()))))
    }

    private var list: some View {
        VStack(spacing: 2) {
            ForEach(entries) { entry in
                Button { onOpen(entry.url) } label: {
                    HStack(spacing: 8) {
                        Image(nsImage: entry.icon).resizable().scaledToFit().frame(width: 20, height: 20)
                        Text(entry.name).lineLimit(1)
                        Spacer()
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
            ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                Button { onOpen(entry.url) } label: {
                    HStack(spacing: 10) {
                        Image(nsImage: entry.icon).resizable().scaledToFit().frame(width: 34, height: 34)
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
}
