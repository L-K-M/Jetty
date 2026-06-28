import Foundation
import Darwin

/// Watches the user's Trash directory for add/remove so the Trash tile can reflect
/// empty vs. full live (IDEA-5). Uses a `DispatchSource` file-system watch (no
/// polling); the callback is delivered on the main queue and coalesces bursts.
final class TrashMonitor {
    /// Called (on the main queue) whenever the Trash's contents change.
    var onChange: (() -> Void)?

    private var source: DispatchSourceFileSystemObject?
    private var fileDescriptor: Int32 = -1

    func start() {
        guard source == nil else { return }
        let path = (try? FileManager.default.url(for: .trashDirectory, in: .userDomainMask,
                                                 appropriateFor: nil, create: false))?.path
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".Trash").path

        let descriptor = open(path, O_EVTONLY)
        guard descriptor >= 0 else { return }
        fileDescriptor = descriptor

        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor, eventMask: [.write, .delete, .rename, .extend], queue: .main)
        src.setEventHandler { [weak self] in self?.onChange?() }
        src.setCancelHandler { [weak self] in
            if let fd = self?.fileDescriptor, fd >= 0 { close(fd) }
            self?.fileDescriptor = -1
        }
        source = src
        src.resume()
    }

    func stop() {
        source?.cancel()   // the cancel handler closes the descriptor
        source = nil
    }
}
