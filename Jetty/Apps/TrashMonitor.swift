import Foundation
import Darwin

/// Watches the user's Trash directories for add/remove so the Trash tile can reflect
/// empty vs. full live (IDEA-5). Uses a `DispatchSource` file-system watch (no
/// polling); the callback is delivered on the main queue and coalesces bursts.
///
/// The watch survives a Trash vnode itself being deleted or swapped out (some
/// "Empty Trash" paths replace the folder): on `.delete`/`.rename` the source is
/// torn down and the path re-opened, and a failed `open()` is logged and retried
/// with backoff instead of silently disabling the tile (F-L11).
final class TrashMonitor {
    /// Called (on the main queue) whenever the Trash's contents change.
    var onChange: (() -> Void)?

    private var sources: [String: DispatchSourceFileSystemObject] = [:]
    private var rearmWork: DispatchWorkItem?
    private var failedPaths = Set<String>()
    private var consecutiveOpenFailures = 0
    private var isRunning = false
    private var notifyAfterAttachment = false

    func start() {
        guard !isRunning else { return }
        isRunning = true
        arm()
    }

    func stop() {
        isRunning = false
        rearmWork?.cancel()
        rearmWork = nil
        failedPaths.removeAll()
        consecutiveOpenFailures = 0
        notifyAfterAttachment = false
        cancelSources()   // the cancel handlers close their descriptors
    }

    /// Re-discovers desired paths after volume/wake changes. Reopen every source so
    /// descriptors left attached to pre-sleep or unmounted vnodes cannot survive.
    func refresh() {
        guard isRunning else { return }
        rearmWork?.cancel()
        rearmWork = nil
        failedPaths.removeAll()
        consecutiveOpenFailures = 0
        cancelSources()   // wake can leave descriptors attached to stale vnodes
        arm(retryFailed: true)
    }

    deinit { stop() }

    // MARK: Arming (re-entrant on vnode swap — F-L11)

    private func arm(retryFailed: Bool = false, verifyAfterArm: Bool = true) {
        guard isRunning else { return }

        let desiredURLs = TrashLocations.watchableTrashURLs()
        let desiredPaths = Set(desiredURLs.map(\.path))
        for path in Array(sources.keys) where !desiredPaths.contains(path) {
            sources.removeValue(forKey: path)?.cancel()
        }
        failedPaths.formIntersection(desiredPaths)

        var attachedRecoveredPath = false
        for url in desiredURLs {
            let path = url.path
            guard sources[path] == nil else { continue }
            guard retryFailed || !failedPaths.contains(path) else { continue }

            let descriptor = open(path, O_EVTONLY)
            guard descriptor >= 0 else {
                failedPaths.insert(path)
                continue
            }
            if failedPaths.remove(path) != nil { attachedRecoveredPath = true }

            let src = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: descriptor,
                eventMask: [.write, .delete, .rename, .extend, .revoke],
                queue: .main)
            src.setEventHandler { [weak self, weak src] in
                guard let self else { return }
                let events = src?.data ?? []
                self.onChange?()
                // The watched vnode itself went away (Trash folder deleted/renamed/recreated):
                // these fds may now point at dead vnodes, so tear down and re-open paths.
                if !events.isDisjoint(with: [.delete, .rename, .revoke]) {
                    self.rearmAfterVnodeSwap()
                } else {
                    // A `.Trashes` parent event may be the user's lazily-created UID
                    // directory; let that child retry immediately instead of waiting
                    // for an unrelated path's backoff.
                    if path.hasSuffix("/.Trashes") {
                        self.failedPaths.remove("\(path)/\(getuid())")
                    }
                    self.arm()
                }
            }
            // Capture the fd *by value* so a rapid stop()/start() can't make this handler
            // close a descriptor that a new monitor is already using (fd reuse race) — H23.
            src.setCancelHandler { if descriptor >= 0 { close(descriptor) } }
            sources[path] = src
            src.resume()
        }

        if attachedRecoveredPath || notifyAfterAttachment {
            notifyAfterAttachment = false
            onChange?()
        }

        guard failedPaths.isEmpty else {
            guard rearmWork == nil else { return }
            consecutiveOpenFailures += 1
            let delay = min(2.0 * Double(consecutiveOpenFailures), 30.0)
            NSLog("Jetty: TrashMonitor could not open \(failedPaths.count) Trash watch path(s); retrying in \(Int(delay))s")
            scheduleRearm(after: delay)
            return
        }
        consecutiveOpenFailures = 0
        rearmWork?.cancel()
        rearmWork = nil

        // Close the discover-before-watch race: every ancestor source is resumed now,
        // so a second discovery on the next main turn either finds a child created in
        // the gap or receives its creation event through the active ancestor source.
        if verifyAfterArm {
            DispatchQueue.main.async { [weak self] in
                self?.arm(verifyAfterArm: false)
            }
        }
    }

    private func rearmAfterVnodeSwap() {
        cancelSources()   // the cancel handlers close their descriptors
        failedPaths.removeAll()
        notifyAfterAttachment = true
        // Give the replacement Trash folder a beat to appear before re-opening.
        scheduleRearm(after: 0.5)
    }

    private func cancelSources() {
        sources.values.forEach { $0.cancel() }
        sources.removeAll()
    }

    private func scheduleRearm(after delay: TimeInterval) {
        rearmWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.rearmWork = nil
            self?.arm(retryFailed: true)
        }
        rearmWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }
}
