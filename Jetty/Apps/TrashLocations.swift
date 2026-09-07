import Foundation
// Darwin only: `getuid()` is used solely by the Finder-shaped candidate list below.
// The XDG path needs no libc, so there is deliberately no `#else` import to keep in
// step with musl or any other non-glibc toolchain.
#if canImport(Darwin)
import Darwin
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
        return XDGPaths.dataHome().appendingPathComponent("Trash", isDirectory: true)
        #endif
    }

    /// Existing directories whose **children are** this user's discarded items:
    /// `~/.Trash` and `.Trashes/$uid` on Darwin, `$XDG_DATA_HOME/Trash/files` under XDG.
    /// For the trash *root* — what a user pins, and what `isTrashURL` matches — use
    /// `userTrashURL()`; off Darwin these sit one level below it.
    ///
    /// **May be empty off Darwin**, where `Trash/files` is not created until the user's
    /// first delete. `~/.Trash` exists from login, so this cannot happen on macOS. A
    /// watch built from this list therefore has to tolerate attaching to nothing and
    /// re-attach once the directory appears — see the note against the Linux Trash tile
    /// in docs/linux-port-plan.md.
    static func existingTrashURLs() -> [URL] {
        unique(trashContentsURLs()).filter(isDirectory)
    }

    /// The directories whose **children are** discarded items — what an emptiness
    /// probe enumerates and what a filesystem watch attaches to.
    ///
    /// Identical to `candidateTrashURLs()` on Darwin, where `~/.Trash` holds the items
    /// directly. Under XDG it is one level deeper: the trash directory holds `files/`
    /// and `info/`, and only `files/` holds items. Probing the root instead would
    /// report "not empty" forever — `files/` and `info/` survive emptying — and a
    /// watch on the root would never see an item arrive inside `files/`.
    static func trashContentsURLs() -> [URL] {
        #if canImport(Darwin)
        return candidateTrashURLs()
        #else
        return candidateTrashURLs().map { $0.appendingPathComponent("files", isDirectory: true) }
        #endif
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
        #if canImport(Darwin)
        let uid = String(getuid())
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
