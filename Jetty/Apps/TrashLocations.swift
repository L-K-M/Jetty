import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

/// Finder's Trash can span the user's home Trash plus per-volume Trash folders. Keep
/// the discovery logic in one place so the icon state and filesystem watch agree.
enum TrashLocations {

    static func userTrashURL() -> URL {
        #if canImport(Darwin)
        return (try? FileManager.default.url(for: .trashDirectory, in: .userDomainMask,
                                             appropriateFor: nil, create: false))
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".Trash", isDirectory: true)
        #else
        // The XDG Trash spec, which is where a Linux desktop actually puts deleted
        // files: `$XDG_DATA_HOME/Trash` (default `~/.local/share/Trash`), holding
        // `files/` and `info/`. Not a fallback for the Cocoa path — a different
        // location, so `.trashDirectory` would be wrong here even if corelibs had it.
        return xdgDataHome().appendingPathComponent("Trash", isDirectory: true)
        #endif
    }

    #if !canImport(Darwin)
    /// `$XDG_DATA_HOME`, or its specified default. Mirrors `DockStore.xdgDataHome`;
    /// a relative value is ignored, as the spec requires.
    static func xdgDataHome() -> URL {
        let value = ProcessInfo.processInfo.environment["XDG_DATA_HOME"]
        if let value, value.hasPrefix("/") { return URL(fileURLWithPath: value) }
        return URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".local/share")
    }
    #endif

    /// Existing Trash folders that can currently contain this user's discarded items.
    static func existingTrashURLs() -> [URL] {
        unique(candidateTrashURLs()).filter(isDirectory)
    }

    /// All plausible Trash folders for this user. Some may not exist; callers that
    /// probe contents should treat missing paths as empty, not omit the candidates up
    /// front, because Finder can create per-volume Trash folders lazily.
    static func candidateTrashURLs() -> [URL] {
        unique(makeCandidateTrashURLs())
    }

    static func isTrashURL(_ url: URL) -> Bool {
        let path = normalizedPath(url)
        return candidateTrashURLs().contains { normalizedPath($0) == path }
    }

    /// URLs worth watching. The home Trash is included even if it disappeared briefly,
    /// so the monitor can retry and reattach after Finder recreates it. Per-volume
    /// `.Trashes` parents are included so a newly-created UID Trash folder is noticed.
    static func watchableTrashURLs() -> [URL] {
        let user = userTrashURL()
        var urls = existingTrashURLs() + existingTrashParentURLs() + rootsMissingTrashParent()
        if !urls.contains(where: { samePath($0, user) }) { urls.insert(user, at: 0) }
        return unique(urls)
    }

    private static func existingTrashParentURLs() -> [URL] {
        mountedVolumes()
            .map { $0.appendingPathComponent(".Trashes", isDirectory: true) }
            .filter(isDirectory)
    }

    /// Finder creates a volume's `.Trashes` directory lazily. Until it exists, watch
    /// the volume root so the monitor sees that first creation and can attach to the
    /// parent/UID directory immediately.
    private static func rootsMissingTrashParent() -> [URL] {
        mountedVolumes().filter {
            !isDirectory($0.appendingPathComponent(".Trashes", isDirectory: true))
        }
    }

    private static func makeCandidateTrashURLs() -> [URL] {
        let uid = String(getuid())
        #if canImport(Darwin)
        let homeTrash = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".Trash", isDirectory: true)
        var urls = [userTrashURL(), homeTrash]
        urls.append(URL(fileURLWithPath: "/.Trashes", isDirectory: true)
            .appendingPathComponent(uid, isDirectory: true))
        urls.append(URL(fileURLWithPath: "/System/Volumes/Data/.Trashes", isDirectory: true)
            .appendingPathComponent(uid, isDirectory: true))
        for volume in mountedVolumes() {
            urls.append(volume.appendingPathComponent(".Trashes", isDirectory: true)
                .appendingPathComponent(uid, isDirectory: true))
        }
        return urls
        #else
        // XDG names the per-volume trash `.Trash-$uid` at the mount root, not
        // `.Trashes/$uid`. Only the home trash is claimed here; wiring up mounted
        // volumes needs their real enumeration (`/proc/mounts`), which belongs with
        // the Linux Trash tile rather than with porting the merge, so a removable
        // drive's trash is simply not recognised yet rather than guessed at.
        _ = uid
        return [userTrashURL()]
        #endif
    }

    private static func mountedVolumes() -> [URL] {
        var urls = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: nil, options: []) ?? []
        urls.append(URL(fileURLWithPath: "/", isDirectory: true))
        urls.append(URL(fileURLWithPath: "/System/Volumes/Data", isDirectory: true))
        return unique(urls)
    }

    private static func isDirectory(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    private static func unique(_ urls: [URL]) -> [URL] {
        var seen = Set<String>()
        var result: [URL] = []
        for url in urls {
            let path = url.standardizedFileURL.path
            if seen.insert(path).inserted { result.append(url) }
        }
        return result
    }

    private static func samePath(_ a: URL, _ b: URL) -> Bool {
        normalizedPath(a) == normalizedPath(b)
    }

    private static func normalizedPath(_ url: URL) -> String {
        url.standardizedFileURL.resolvingSymlinksInPath().path
    }
}
