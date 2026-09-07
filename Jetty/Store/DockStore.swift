import Foundation
// Off Darwin there is no Combine, and `ObservableObject`/`@Published` below come from
// `Common/ObservationCompat.swift` — JP-02's shim, which defines them under the
// mirrored `#if !canImport(Combine)`.
#if canImport(Combine)
import Combine
#endif
// `moveItem` below calls SwiftUI's `move(fromOffsets:toOffset:)`, so this file needs
// SwiftUI under exactly the condition that call is gated on.
#if canImport(SwiftUI)
import SwiftUI
#endif

/// Loads and saves the `DockDocument` (pinned items + per-display anchors) as JSON
/// in Application Support. Writes are **atomic** and **debounced**, keeping one
/// `.bak` of the prior good file so a crash mid-write can't lose the layout.
/// `@Published document` lets SwiftUI settings update live. See PLAN.md §6, §11.
final class DockStore: ObservableObject {

    @Published private(set) var document: DockDocument

    /// True when an existing document was read from disk (vs. a fresh first run).
    let loadedFromDisk: Bool

    /// True when the file on disk claims a **newer** document version than this build
    /// understands (`version > DockDocument.currentVersion`). In that case the store
    /// never writes: re-encoding would rewrite downgraded (lossily decoded) content
    /// under the newer version stamp — and rotate the real newer file out of `.bak` —
    /// poisoning a future build's migration (FAB-B16). In-memory edits still work for
    /// the session; they just aren't persisted.
    let isReadOnly: Bool

    private let fileURL: URL
    private let fileManager: FileManager
    private var saveWorkItem: DispatchWorkItem?
    private let debounce: TimeInterval

    init(fileURL: URL = DockStore.defaultURL, fileManager: FileManager = .default, debounce: TimeInterval = 0.4) {
        self.fileURL = fileURL
        self.fileManager = fileManager
        self.debounce = debounce
        if let loaded = Self.load(from: fileURL, fileManager: fileManager) {
            document = loaded
            loadedFromDisk = true
            isReadOnly = loaded.version > DockDocument.currentVersion
        } else {
            document = DockDocument()
            loadedFromDisk = false
            isReadOnly = false
        }
        if isReadOnly {
            NSLog("Jetty: dock.json is version \(document.version) but this build only understands version \(DockDocument.currentVersion) — treating the store as read-only for this session so the newer file isn't downgraded.")
        }
    }

    // MARK: Reads

    var items: [DockItem] { document.items }

    func contains(bundleIdentifier: String) -> Bool {
        document.items.contains { $0.kind == .application && $0.bundleIdentifier == bundleIdentifier }
    }

    /// The stored per-display anchor override, if any (nil → use the global default).
    func anchorOverride(forDisplayUUID uuid: String) -> DockAnchor? {
        document.anchorsByDisplayUUID[uuid]
    }

    /// Whether the user has opted this display out of showing a dock. Note this is the
    /// raw preference; `DockController` still shows a dock here if it would otherwise be
    /// the only display left without one.
    func isDisplayDisabled(forDisplayUUID uuid: String) -> Bool {
        document.disabledDisplayUUIDs.contains(uuid)
    }

    /// Resolves a pinned item to its current URL via its bookmark (tracking moves),
    /// and — crucially — **writes back** a freshened bookmark when the stored one was
    /// stale, so a moved file/app keeps working on later launches instead of silently
    /// going stale in `dock.json` (ISSUE-7). Returns nil if unknown/unresolvable.
    func resolvedURL(forItemID id: UUID) -> URL? {
        guard let item = document.items.first(where: { $0.id == id }),
              let (url, isStale) = BookmarkResolver.resolve(item) else { return nil }
        if isStale, let fresh = BookmarkResolver.bookmark(for: url),
           let index = document.items.firstIndex(where: { $0.id == id }) {
            document.items[index].bookmark = fresh
            document.items[index].url = url
            scheduleSave()
        }
        return url
    }

    // MARK: Mutations

    func setItems(_ items: [DockItem]) {
        document.items = items
        scheduleSave()
    }

    func addItem(_ item: DockItem, at index: Int? = nil) {
        if let index, index >= 0, index <= document.items.count {
            document.items.insert(item, at: index)
        } else {
            document.items.append(item)
        }
        scheduleSave()
    }

    func removeItem(id: UUID) {
        document.items.removeAll { $0.id == id }
        scheduleSave()
    }

    /// Renames a pinned item (MF-7).
    func rename(id: UUID, to name: String) {
        guard let index = document.items.firstIndex(where: { $0.id == id }) else { return }
        document.items[index].displayName = name
        scheduleSave()
    }

    /// Sets (or clears, with `nil`) a pinned item's custom icon path (MF-7).
    func setCustomIconPath(_ path: String?, id: UUID) {
        guard let index = document.items.firstIndex(where: { $0.id == id }) else { return }
        document.items[index].customIconPath = path
        scheduleSave()
    }

    /// Sets how a pinned folder's stack popover presents its contents (MF-2).
    func setFolderDisplay(_ style: FolderStackStyle, id: UUID) {
        guard let index = document.items.firstIndex(where: { $0.id == id }) else { return }
        document.items[index].folderDisplay = style
        scheduleSave()
    }

    /// Reorders via SwiftUI list offsets, for `ItemsView`'s `.onMove`.
    ///
    /// macOS-only, and deliberately not ported: `move(fromOffsets:toOffset:)` is
    /// SwiftUI's, not the standard library's, so it does not exist on Linux. The
    /// portable move is to hand `setItems` an explicit order, which is what
    /// `DockController.reorder(to:)` — the dock's own drag-to-reorder — already does,
    /// and what a Linux settings UI would do too. Re-implementing Apple's offset
    /// semantics here would buy nothing for that caller while risking a silent change
    /// to shipped drag behaviour that no test covers.
    #if canImport(SwiftUI)
    func moveItem(fromOffsets source: IndexSet, toOffset destination: Int) {
        document.items.move(fromOffsets: source, toOffset: destination)
        scheduleSave()
    }
    #endif

    func setAnchor(_ anchor: DockAnchor, forDisplayUUID uuid: String) {
        document.anchorsByDisplayUUID[uuid] = anchor
        scheduleSave()
    }

    func clearAnchor(forDisplayUUID uuid: String) {
        document.anchorsByDisplayUUID[uuid] = nil
        scheduleSave()
    }

    func setDisplayDisabled(_ disabled: Bool, forDisplayUUID uuid: String) {
        if disabled { document.disabledDisplayUUIDs.insert(uuid) }
        else { document.disabledDisplayUUIDs.remove(uuid) }
        scheduleSave()
    }

    func replaceDocument(_ doc: DockDocument) {
        document = doc
        scheduleSave()
    }

    // MARK: Saving

    /// Forces a pending save to disk immediately (e.g. at app termination).
    func flush() {
        saveWorkItem?.cancel()
        saveWorkItem = nil
        saveNow()
    }

    private func scheduleSave() {
        saveWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.saveNow() }
        saveWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + debounce, execute: work)
    }

    private func saveNow() {
        // Never overwrite a file written by a newer build (FAB-B16): this build's
        // encode would be a lossy downgrade of content it only partially understands.
        guard !isReadOnly else {
            NSLog("Jetty: skipping save — dock.json is version \(document.version) (newer than this build's \(DockDocument.currentVersion)); the store is read-only this session.")
            return
        }
        do {
            try fileManager.createDirectory(at: fileURL.deletingLastPathComponent(),
                                            withIntermediateDirectories: true)
            // Keep one backup of the prior good file — but ONLY snapshot a primary that
            // still decodes. Otherwise a corrupt primary (which we may have just
            // recovered from `.bak`) would overwrite the last good backup (ISSUE-9).
            if fileManager.fileExists(atPath: fileURL.path), Self.fileDecodes(fileURL) {
                try rotateBackup()
            }
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            // Stamp the version truthfully (FAB-B16): what this build writes is, by
            // definition, `currentVersion`-shaped — never echo an older file's stamp.
            var toWrite = document
            toWrite.version = DockDocument.currentVersion
            let data = try encoder.encode(toWrite)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            NSLog("Jetty: failed to save dock document: \(error.localizedDescription)")
        }
    }

    /// Copies the current good primary to a verified sibling, then atomically replaces
    /// `.bak`. The prior backup remains untouched if copy or validation fails.
    private func rotateBackup() throws {
        let backupURL = fileURL.appendingPathExtension("bak")
        let candidateURL = backupURL.deletingLastPathComponent().appendingPathComponent(
            ".\(backupURL.lastPathComponent).tmp-\(UUID().uuidString)")
        defer { try? fileManager.removeItem(at: candidateURL) }

        try fileManager.copyItem(at: fileURL, to: candidateURL)
        guard Self.fileDecodes(candidateURL) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        // Promote the verified snapshot with an atomic write, not `replaceItemAt`.
        //
        // `replaceItemAt` is unusable in swift-corelibs-foundation: it throws *and*
        // deletes the destination. Since this call sits inside `saveNow`'s do-block,
        // the throw also skipped the primary write below it — so on Linux every save
        // from the **third** onward (the first with an existing `.bak` to replace)
        // destroyed the backup and silently persisted nothing at all. The suite missed
        // it because its round-trip test stops at the second save, where this branch
        // creates `.bak` instead of replacing it; `testThirdSaveReplacesAnExistingBackup`
        // covers it now.
        //
        // `Data.write(options: .atomic)` is a temp-file-plus-rename on both platforms —
        // measured, by watching the destination's inode change — which is the only
        // property `replaceItemAt` was here for, and it creates or replaces alike, so
        // the two branches collapse into one.
        try Data(contentsOf: candidateURL).write(to: backupURL, options: .atomic)
    }

    // MARK: Loading

    static func load(from url: URL, fileManager: FileManager = .default) -> DockDocument? {
        func decode(_ u: URL) -> DockDocument? {
            guard let data = try? Data(contentsOf: u) else { return nil }
            return try? JSONDecoder().decode(DockDocument.self, from: data)
        }
        if let doc = decode(url) { return doc }
        // Fall back to the backup if the primary is missing/corrupt.
        return decode(url.appendingPathExtension("bak"))
    }

    /// Whether the file at `url` exists and decodes as a `DockDocument` — used to avoid
    /// backing up a corrupt primary over the last good backup (ISSUE-9).
    static func fileDecodes(_ url: URL) -> Bool {
        guard let data = try? Data(contentsOf: url) else { return false }
        return (try? JSONDecoder().decode(DockDocument.self, from: data)) != nil
    }

    /// `~/Library/Application Support/Jetty/dock.json` on macOS, and
    /// `$XDG_DATA_HOME/Jetty/dock.json` (default `~/.local/share`) on Linux — with no
    /// branch needed for the common path, because swift-corelibs-foundation already
    /// maps `.applicationSupportDirectory` onto XDG. Measured on the pinned toolchain.
    ///
    /// Only the fallback, for when that lookup throws, has to know where it is: the
    /// hardcoded `Library/Application Support` would put a Linux dock file in a
    /// macOS-shaped path that nothing else would ever look in.
    static var defaultURL: URL {
        #if canImport(Darwin)
        let fallback = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Application Support")
        #else
        let fallback = xdgDataHome(ProcessInfo.processInfo.environment["XDG_DATA_HOME"],
                                   home: NSHomeDirectory())
        #endif
        let base = (try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                 appropriateFor: nil, create: true))
            ?? fallback
        return base.appendingPathComponent("Jetty", isDirectory: true).appendingPathComponent("dock.json")
    }

    /// The XDG base-directory rule for `$XDG_DATA_HOME`, used only by `defaultURL`'s
    /// Linux fallback — the one branch that picks a path itself rather than asking
    /// Foundation. It matters precisely because that branch runs when the lookup
    /// throws, which is when the environment is unusual: hardcoding `~/.local/share`
    /// there would put `dock.json` somewhere nothing else, including corelibs itself,
    /// would look.
    ///
    /// The spec has two rules beyond "read the variable", and both are here: an unset
    /// **or empty** value falls back to `$HOME/.local/share`, and a **relative** value
    /// is invalid and must be ignored rather than resolved against the working
    /// directory. Pure and unconditional so both platforms test it.
    static func xdgDataHome(_ value: String?, home: String) -> URL {
        XDGPaths.dataHome(value, home: home)
    }
}
