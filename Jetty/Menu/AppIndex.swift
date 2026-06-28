import AppKit
import Combine

/// Builds and caches the list of installed applications for the Jetty Menu's search,
/// scanning the standard application directories off the main thread. (A Spotlight
/// `NSMetadataQuery` could widen this to apps anywhere — a later refinement.) See
/// PLAN.md §8.2.
final class AppIndex: ObservableObject {

    @Published private(set) var apps: [AppSearchItem] = []

    init() { reload() }

    func reload() {
        DispatchQueue.global(qos: .userInitiated).async {
            let found = Self.scan()
            DispatchQueue.main.async { self.apps = found }
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

        var items: [AppSearchItem] = []
        var seen = Set<String>()

        func add(_ url: URL) {
            let bundleID = Bundle(url: url)?.bundleIdentifier
            let key = bundleID ?? url.path
            guard !seen.contains(key) else { return }
            seen.insert(key)
            items.append(AppSearchItem(name: url.deletingPathExtension().lastPathComponent,
                                       bundleID: bundleID, url: url))
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
        return items.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}
