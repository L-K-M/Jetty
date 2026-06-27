import AppKit

/// Hides (and restores) the **real** macOS Dock so Jetty's dock can take its place.
///
/// There is no public API to disable the Dock, and injecting into it requires
/// disabling SIP — both off-limits. The proven, SIP-safe, reversible approach every
/// shipping replacement uses is to set the Dock to auto-hide with a *very large*
/// reveal delay, so it stays alive (Mission Control / Spaces / minimize keep
/// working) but is effectively off-screen. We re-assert on launch/wake because
/// macOS — especially Tahoe — can reset or glitch auto-hide, and we keep a clean
/// one-click restore. See PLAN.md §0, §10.
final class SystemDockController {

    private let dockDefaults = UserDefaults(suiteName: "com.apple.dock")
    private let ourDefaults: UserDefaults
    private let largeDelay = 1000.0

    private enum Key {
        static let isManaging = "SystemDock.isManaging"
        static let priorAutohide = "SystemDock.priorAutohide"
        static let capturedPrior = "SystemDock.capturedPrior"
    }

    init(ourDefaults: UserDefaults = .standard) {
        self.ourDefaults = ourDefaults
    }

    /// Whether Jetty currently has the system Dock hidden.
    var isManaging: Bool { ourDefaults.bool(forKey: Key.isManaging) }

    /// Hides the system Dock (auto-hide + huge reveal delay) and restarts it once to
    /// apply. Captures the user's prior auto-hide setting so `restore()` is faithful.
    func hideSystemDock() {
        guard let dockDefaults else { return }
        if !ourDefaults.bool(forKey: Key.capturedPrior) {
            ourDefaults.set(dockDefaults.bool(forKey: "autohide"), forKey: Key.priorAutohide)
            ourDefaults.set(true, forKey: Key.capturedPrior)
        }
        dockDefaults.set(true, forKey: "autohide")
        dockDefaults.set(largeDelay, forKey: "autohide-delay")
        dockDefaults.set(0.0, forKey: "autohide-time-modifier")
        ourDefaults.set(true, forKey: Key.isManaging)
        restartDock()
    }

    /// Re-applies the hide settings without restarting the Dock unless they drifted —
    /// call on launch, wake, and screen changes to survive Tahoe's auto-hide glitches.
    func reassertIfManaging() {
        guard isManaging, let dockDefaults else { return }
        let delay = dockDefaults.double(forKey: "autohide-delay")
        let hidden = dockDefaults.bool(forKey: "autohide")
        if !hidden || delay < largeDelay - 1 {
            dockDefaults.set(true, forKey: "autohide")
            dockDefaults.set(largeDelay, forKey: "autohide-delay")
            dockDefaults.set(0.0, forKey: "autohide-time-modifier")
            restartDock()
        }
    }

    /// Restores the system Dock to the user's prior state (removes the long delay,
    /// restores their auto-hide setting) and restarts it.
    func restoreSystemDock() {
        guard let dockDefaults else { return }
        let priorAutohide = ourDefaults.object(forKey: Key.priorAutohide) as? Bool ?? false
        dockDefaults.removeObject(forKey: "autohide-delay")
        dockDefaults.removeObject(forKey: "autohide-time-modifier")
        dockDefaults.set(priorAutohide, forKey: "autohide")
        ourDefaults.set(false, forKey: Key.isManaging)
        ourDefaults.set(false, forKey: Key.capturedPrior)
        restartDock()
    }

    /// `killall Dock` — launchd respawns it within ~1s with the new settings. Called
    /// only to *apply* a defaults change, never as an ongoing strategy. (This does
    /// not disturb ⌘-Tab, which is handled at the loginwindow level.)
    private func restartDock() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        process.arguments = ["Dock"]
        do { try process.run() } catch { NSLog("Jetty: killall Dock failed: \(error.localizedDescription)") }
    }
}
