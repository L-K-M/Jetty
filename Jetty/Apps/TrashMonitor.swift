import Foundation
import Darwin

/// Watches the user's Trash directory for add/remove so the Trash tile can reflect
/// empty vs. full live (IDEA-5). Uses a `DispatchSource` file-system watch (no
/// polling); the callback is delivered on the main queue and coalesces bursts.
final class TrashMonitor {
    /// Called (on the main queue) whenever the Trash's contents change.
    var onChange: (() -> Void)?

    private var source: DispatchSourceFileSystemObject?

    func start() {
        guard source == nil else { return }
        let path = (try? FileManager.default.url(for: .trashDirectory, in: .userDomainMask,
                                                 appropriateFor: nil, create: false))?.path
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".Trash").path

        let descriptor = open(path, O_EVTONLY)
        guard descriptor >= 0 else { return }

        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor, eventMask: [.write, .delete, .rename, .extend], queue: .main)
        src.setEventHandler { [weak self] in self?.onChange?() }
        // Capture the fd *by value* so a rapid stop()/start() can't make this handler
        // close a descriptor that a new monitor is already using (fd reuse race) — H23.
        src.setCancelHandler { if descriptor >= 0 { close(descriptor) } }
        source = src
        src.resume()
    }

    func stop() {
        source?.cancel()   // the cancel handler closes the descriptor
        source = nil
    }

    deinit { stop() }
}
