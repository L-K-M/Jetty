import Foundation
import AppKit

/// One pinned entry in the dock. Identity is a `UUID` so items survive rename and
/// reorder. File/folder/app targets are held as security-scoped-ready **bookmarks**
/// (with a plain `url` fallback) so they survive the target moving. See PLAN.md §6.
struct DockItem: Codable, Identifiable, Equatable {
    let id: UUID
    var kind: DockItemKind
    var displayName: String
    var bookmark: Data?
    var url: URL?
    var bundleIdentifier: String?
    var folderDisplay: FolderStackStyle?
    /// Path to a user-chosen image that overrides the default icon (MF-7).
    var customIconPath: String?

    init(id: UUID = UUID(),
         kind: DockItemKind,
         displayName: String = "",
         bookmark: Data? = nil,
         url: URL? = nil,
         bundleIdentifier: String? = nil,
         folderDisplay: FolderStackStyle? = nil,
         customIconPath: String? = nil) {
        self.id = id
        self.kind = kind
        self.displayName = displayName
        self.bookmark = bookmark
        self.url = url
        self.bundleIdentifier = bundleIdentifier
        self.folderDisplay = folderDisplay
        self.customIconPath = customIconPath
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        kind = try c.decode(DockItemKind.self, forKey: .kind)
        displayName = try c.decodeIfPresent(String.self, forKey: .displayName) ?? ""
        bookmark = try c.decodeIfPresent(Data.self, forKey: .bookmark)
        url = try c.decodeIfPresent(URL.self, forKey: .url)
        bundleIdentifier = try c.decodeIfPresent(String.self, forKey: .bundleIdentifier)
        folderDisplay = try c.decodeIfPresent(FolderStackStyle.self, forKey: .folderDisplay)
        customIconPath = try c.decodeIfPresent(String.self, forKey: .customIconPath)
    }

    private enum CodingKeys: String, CodingKey {
        case id, kind, displayName, bookmark, url, bundleIdentifier, folderDisplay, customIconPath
    }

    /// A stable identity used to dedup a pinned app against the same app appearing
    /// in the running-apps list (match by bundle id when present).
    var dedupKey: String {
        if kind == .application, let bundleIdentifier { return "app:\(bundleIdentifier)" }
        return "item:\(id.uuidString)"
    }

    // MARK: Factories

    /// A pinned application from its on-disk URL (`/Applications/Safari.app`).
    static func application(at url: URL, name: String? = nil, bundleIdentifier: String? = nil) -> DockItem {
        DockItem(kind: .application,
                 displayName: name ?? url.deletingPathExtension().lastPathComponent,
                 url: url,
                 bundleIdentifier: bundleIdentifier ?? Bundle(url: url)?.bundleIdentifier)
    }

    /// A pinned file or folder from a URL.
    static func fromFileURL(_ url: URL) -> DockItem {
        var isDir: ObjCBool = false
        FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
        let kind: DockItemKind = url.pathExtension == "app" ? .application : (isDir.boolValue ? .folder : .file)
        return DockItem(kind: kind,
                        displayName: url.deletingPathExtension().lastPathComponent,
                        url: url,
                        bundleIdentifier: kind == .application ? Bundle(url: url)?.bundleIdentifier : nil,
                        folderDisplay: kind == .folder ? .grid : nil)
    }

    /// A pinned web/deeplink tile.
    static func fromLink(_ url: URL, name: String? = nil) -> DockItem {
        DockItem(kind: .url, displayName: name ?? url.host ?? url.absoluteString, url: url)
    }
}
