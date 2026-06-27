import AppKit
import Combine

/// A lightweight, value-type snapshot of a running application — enough to build a
/// dock tile and dedup against pinned items, with no AppKit references so the tile
/// merge stays pure and testable.
struct RunningAppInfo: Equatable, Identifiable {
    var bundleIdentifier: String?
    var name: String
    var isActive: Bool
    var pid: pid_t

    var id: String { bundleIdentifier ?? "pid:\(pid)" }
}

/// Tracks the set of "ordinary" running apps (the ones a Dock shows) and keeps it
/// live via `NSWorkspace` notifications. Permission-free — this is the backbone of
/// Jetty's running-app tiles and indicators. See PLAN.md §7.
final class RunningAppsModel: ObservableObject {

    @Published private(set) var apps: [RunningAppInfo] = []

    private let workspace: NSWorkspace
    private var observers: [NSObjectProtocol] = []

    init(workspace: NSWorkspace = .shared) {
        self.workspace = workspace
        refresh()
        observe()
    }

    deinit { observers.forEach { workspace.notificationCenter.removeObserver($0) } }

    private func observe() {
        let nc = workspace.notificationCenter
        let names: [NSNotification.Name] = [
            NSWorkspace.didLaunchApplicationNotification,
            NSWorkspace.didTerminateApplicationNotification,
            NSWorkspace.didActivateApplicationNotification,
            NSWorkspace.didDeactivateApplicationNotification,
            NSWorkspace.didHideApplicationNotification,
            NSWorkspace.didUnhideApplicationNotification,
        ]
        for name in names {
            let token = nc.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.refresh()
            }
            observers.append(token)
        }
    }

    /// Rebuilds the snapshot from `runningApplications`, keeping only `.regular`
    /// (Dock-worthy) apps and excluding Jetty itself.
    func refresh() {
        let ownBundleID = Bundle.main.bundleIdentifier
        apps = workspace.runningApplications
            .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != ownBundleID }
            .map { RunningAppInfo(bundleIdentifier: $0.bundleIdentifier,
                                  name: $0.localizedName ?? "App",
                                  isActive: $0.isActive,
                                  pid: $0.processIdentifier) }
    }

    /// The live `NSRunningApplication` for a bundle id (for activate/hide/quit).
    func runningApplication(bundleIdentifier: String) -> NSRunningApplication? {
        workspace.runningApplications.first { $0.bundleIdentifier == bundleIdentifier }
    }

    func runningApplication(pid: pid_t) -> NSRunningApplication? {
        NSRunningApplication(processIdentifier: pid)
    }
}
