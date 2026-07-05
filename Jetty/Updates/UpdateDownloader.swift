import Foundation

/// Downloads a release asset into the user's Downloads folder, picking a
/// non-colliding filename. Reusable across apps — depends only on Foundation.
struct UpdateDownloader {
    var session: URLSession = .shared
    var fileManager: FileManager = .default

    enum DownloadError: LocalizedError {
        case noUniqueFileName(directory: String, fileName: String, attempts: Int)

        var errorDescription: String? {
            switch self {
            case .noUniqueFileName(let directory, let fileName, let attempts):
                return "Couldn't find an unused name for \(fileName) in \(directory) after \(attempts) attempts."
            }
        }
    }

    /// Upper bound on the `Foo-N.ext` collision search — high enough that a real
    /// Downloads folder never hits it, low enough that a directory stuffed with
    /// colliding names (malicious or otherwise) can't spin the loop indefinitely.
    static let maxUniqueNameAttempts = 10_000

    /// Downloads `asset` to `~/Downloads`, returning the saved file URL.
    func downloadToDownloads(_ asset: GitHubRelease.Asset) async throws -> URL {
        let (tempURL, response) = try await session.download(from: asset.browserDownloadURL)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            // Don't abandon a (potentially DMG-sized) error body in the temp dir.
            try? FileManager.default.removeItem(at: tempURL)
            throw GitHubReleaseClient.ClientError.badResponse(http.statusCode)
        }
        let downloads = try fileManager.url(for: .downloadsDirectory, in: .userDomainMask,
                                            appropriateFor: nil, create: true)
        let destination = try Self.uniqueDestination(in: downloads, fileName: asset.name,
                                                     fileManager: fileManager)
        try fileManager.moveItem(at: tempURL, to: destination)
        return destination
    }

    /// A non-colliding URL in `directory` for `fileName` (`Foo.dmg`, then `Foo-1.dmg`,
    /// `Foo-2.dmg`, …) so re-downloading never clobbers an existing file. Throws
    /// `DownloadError.noUniqueFileName` if every candidate up to `maxAttempts` is taken.
    static func uniqueDestination(in directory: URL, fileName: String,
                                  fileManager: FileManager = .default,
                                  maxAttempts: Int = UpdateDownloader.maxUniqueNameAttempts) throws -> URL {
        let name = sanitizedFileName(fileName)
        let first = directory.appendingPathComponent(name)
        guard itemExists(at: first, fileManager: fileManager) else { return first }

        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        for index in 1...max(1, maxAttempts) {
            let candidateName = ext.isEmpty ? "\(base)-\(index)" : "\(base)-\(index).\(ext)"
            let candidate = directory.appendingPathComponent(candidateName)
            if !itemExists(at: candidate, fileManager: fileManager) { return candidate }
        }
        throw DownloadError.noUniqueFileName(directory: directory.path, fileName: name,
                                             attempts: max(1, maxAttempts))
    }

    /// Whether *anything* — file, directory, or symlink (dangling or not) — occupies
    /// `url`. `fileExists(atPath:)` follows symlinks, so a dangling symlink reports
    /// false and `moveItem` would then fail (or, worse, the link could be swapped to
    /// point elsewhere). `attributesOfItem(atPath:)` has `lstat` semantics: it reports
    /// the symlink itself without following it.
    private static func itemExists(at url: URL, fileManager: FileManager) -> Bool {
        (try? fileManager.attributesOfItem(atPath: url.path)) != nil
    }

    /// GitHub asset names should be filenames, but sanitize defensively before
    /// writing into Downloads so path separators/control characters never matter.
    static func sanitizedFileName(_ fileName: String) -> String {
        let candidate = (fileName as NSString).lastPathComponent
        let filtered = candidate.unicodeScalars.map { scalar in
            CharacterSet.controlCharacters.contains(scalar) ? "-" : String(scalar)
        }.joined()
        let trimmed = filtered.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != ".", trimmed != ".." else { return "Jetty-update" }
        return trimmed
    }
}
