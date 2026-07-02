import AppKit
import Combine

/// Builds and caches the list of installed applications for the Jetty Menu's search,
/// scanning the standard application directories off the main thread. (A Spotlight
/// `NSMetadataQuery` could widen this to apps anywhere — a later refinement.) See
/// PLAN.md §8.2.
final class AppIndex: ObservableObject {

    @Published private(set) var apps: [AppSearchItem] = []

    /// Bumped on each `reload()` so an earlier, slower scan that finishes after a later
    /// one can't clobber the newer result. `reload()` runs on the main thread (init /
    /// menu open), so this is only ever touched there — no locking needed (H25).
    private var reloadGeneration = 0

    init() { reload() }

    func reload() {
        reloadGeneration += 1
        let generation = reloadGeneration
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let found = Self.scan()
            DispatchQueue.main.async {
                guard let self, generation == self.reloadGeneration else { return }
                self.apps = found
            }
        }
    }

    static func scan() -> [AppSearchItem] {
        let fm = FileManager.default
        var dirs: [URL] = [
            URL(fileURLWithPath: "/Applications"),
            URL(fileURLWithPath: "/Applications/Utilities"),
            URL(fileURLWithPath: "/System/Applications"),
            URL(fileURLWithPath: "/System/Applications/Utilities"),
        ]
        if let userApps = try? fm.url(for: .applicationDirectory, in: .userDomainMask,
                                      appropriateFor: nil, create: false) {
            dirs.append(userApps)
        }
        // For a non-sandboxed app, `.applicationDirectory`/`.userDomainMask` resolves to
        // `/Applications` (the local domain), *not* `~/Applications` — so add the real
        // per-user folder explicitly (many Homebrew casks / drag-installs live there) — H3.
        dirs.append(URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Applications"))

        var items: [AppSearchItem] = []
        var seen = Set<String>()

        func add(_ url: URL) {
            let bundle = Bundle(url: url)
            let bundleID = bundle?.bundleIdentifier
            let key = bundleID ?? url.path
            guard !seen.contains(key) else { return }
            seen.insert(key)
            // Prefer the localized display name (`CFBundleDisplayName`, then `CFBundleName`)
            // over the raw filename so search matches what the user actually sees — H5.
            let name = (bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
                ?? (bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String)
                ?? url.deletingPathExtension().lastPathComponent
            items.append(AppSearchItem(name: name, bundleID: bundleID, url: url))
        }

        for dir in dirs {
            guard let contents = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.isDirectoryKey],
                                                             options: [.skipsHiddenFiles]) else { continue }
            for url in contents {
                if url.pathExtension == "app" {
                    add(url)
                } else if (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                    // One level deeper, e.g. /Applications/SomeVendor/App.app (ISSUE-6).
                    let sub = (try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: nil,
                                                           options: [.skipsHiddenFiles])) ?? []
                    for child in sub where child.pathExtension == "app" { add(child) }
                }
            }
        }

        // Finder lives in CoreServices, not an Applications folder, so a plain scan of
        // the dirs above never finds it — typing "Finder" turned up nothing. Add it (and
        // its CoreServices/Applications siblings like Screen Sharing) explicitly rather
        // than scanning all of CoreServices, which is full of internal helper .apps (F-L4).
        for path in ["/System/Library/CoreServices/Finder.app"] where fm.fileExists(atPath: path) {
            add(URL(fileURLWithPath: path))
        }
        if let coreServiceApps = try? fm.contentsOfDirectory(
            at: URL(fileURLWithPath: "/System/Library/CoreServices/Applications"),
            includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
            for url in coreServiceApps where url.pathExtension == "app" { add(url) }
        }
        return items.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}
