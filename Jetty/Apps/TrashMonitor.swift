import Foundation
import Darwin

/// Watches the user's Trash directory for add/remove so the Trash tile can reflect
/// empty vs. full live (IDEA-5). Uses a `DispatchSource` file-system watch (no
/// polling); the callback is delivered on the main queue and coalesces bursts.
///
/// The watch survives the Trash vnode itself being deleted or swapped out (some
/// "Empty Trash" paths replace the folder): on `.delete`/`.rename` the source is
/// torn down and the path re-opened, and a failed `open()` is logged and retried
/// with backoff instead of silently disabling the tile (F-L11).
final class TrashMonitor {
    /// Called (on the main queue) whenever the Trash's contents change.
    var onChange: (() -> Void)?

    private var source: DispatchSourceFileSystemObject?
    private var rearmWork: DispatchWorkItem?
    private var consecutiveOpenFailures = 0
    private var isRunning = false

    func start() {
        guard !isRunning else { return }
        isRunning = true
        arm()
    }

    func stop() {
        isRunning = false
        rearmWork?.cancel()
        rearmWork = nil
        consecutiveOpenFailures = 0
        source?.cancel()   // the cancel handler closes the descriptor
        source = nil
    }

    deinit { stop() }

    // MARK: Arming (re-entrant on vnode swap — F-L11)

    private func arm() {
        guard isRunning, source == nil else { return }
        let path = (try? FileManager.default.url(for: .trashDirectory, in: .userDomainMask,
                                                 appropriateFor: nil, create: false))?.path
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".Trash").path

        let descriptor = open(path, O_EVTONLY)
        guard descriptor >= 0 else {
            consecutiveOpenFailures += 1
            let delay = min(2.0 * Double(consecutiveOpenFailures), 30.0)
            NSLog("Jetty: TrashMonitor could not open \(path) (errno \(errno)); retrying in \(Int(delay))s")
            scheduleRearm(after: delay)
            return
        }
        consecutiveOpenFailures = 0

        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor, eventMask: [.write, .delete, .rename, .extend], queue: .main)
        src.setEventHandler { [weak self, weak src] in
            guard let self else { return }
            let events = src?.data ?? []
            self.onChange?()
            // The watched vnode itself went away (Trash folder deleted/renamed/recreated):
            // this fd now points at a dead vnode, so tear down and re-open the path.
            if !events.isDisjoint(with: [.delete, .rename]) {
                self.rearmAfterVnodeSwap()
            }
        }
        // Capture the fd *by value* so a rapid stop()/start() can't make this handler
        // close a descriptor that a new monitor is already using (fd reuse race) — H23.
        src.setCancelHandler { if descriptor >= 0 { close(descriptor) } }
        source = src
        src.resume()
    }

    private func rearmAfterVnodeSwap() {
        source?.cancel()   // the cancel handler closes the descriptor
        source = nil
        // Give the replacement Trash folder a beat to appear before re-opening.
        scheduleRearm(after: 0.5)
    }

    private func scheduleRearm(after delay: TimeInterval) {
        rearmWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.arm() }
        rearmWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }
}
