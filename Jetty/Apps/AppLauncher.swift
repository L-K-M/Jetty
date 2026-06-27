import AppKit

/// Launching, activating, and lifecycle control for dock tiles — all via public
/// `NSWorkspace` / `NSRunningApplication`, so the core dock needs **no permission**.
/// See PLAN.md §7.
enum AppLauncher {

    /// Opens a pinned item: launches/activates an app, or opens a file/folder/url.
    static func open(_ item: DockItem) {
        switch item.kind {
        case .application:
            if let bundleID = item.bundleIdentifier,
               let running = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == bundleID }) {
                activate(running)
            } else if let url = resolvedURL(item) {
                launchApplication(at: url)
            }
        case .file, .folder, .url:
            if let url = resolvedURL(item) { NSWorkspace.shared.open(url) }
        case .trash:
            openTrash()
        case .separator, .clock, .jettyMenu:
            break
        }
    }

    static func launchApplication(at url: URL) {
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: config, completionHandler: nil)
    }

    /// Brings an already-running app forward without yanking focus more than needed.
    static func activate(_ app: NSRunningApplication) {
        if #available(macOS 14.0, *) {
            app.activate(options: [.activateAllWindows])
        } else {
            app.activate(options: [.activateIgnoringOtherApps, .activateAllWindows])
        }
    }

    static func hide(_ app: NSRunningApplication) { app.hide() }
    static func quit(_ app: NSRunningApplication) { app.terminate() }

    /// Opens `files` with the application at `appURL` (drag-a-file-onto-a-tile).
    static func open(_ files: [URL], withApplicationAt appURL: URL) {
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        NSWorkspace.shared.open(files, withApplicationAt: appURL, configuration: config, completionHandler: nil)
    }

    static func openTrash() {
        let trash = (try? FileManager.default.url(for: .trashDirectory, in: .userDomainMask,
                                                  appropriateFor: nil, create: false))
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".Trash")
        NSWorkspace.shared.open(trash)
    }

    /// Moves `urls` to the Trash (the drop-on-Trash action). Returns the count moved.
    @discardableResult
    static func moveToTrash(_ urls: [URL]) -> Int {
        var moved = 0
        for url in urls {
            do { try FileManager.default.trashItem(at: url, resultingItemURL: nil); moved += 1 }
            catch { NSLog("Jetty: trash failed for \(url.lastPathComponent): \(error.localizedDescription)") }
        }
        return moved
    }

    static func resolvedURL(_ item: DockItem) -> URL? {
        BookmarkResolver.resolve(item)?.url
    }
}
