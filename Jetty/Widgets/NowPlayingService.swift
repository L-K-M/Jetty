import Foundation

/// A snapshot of the system "now playing" track.
struct NowPlayingSnapshot: Equatable {
    let title: String
    let artist: String?
    let isPlaying: Bool
}

/// Reads the system now-playing track via the Objective-C `JettyNowPlaying` bridge
/// (private MediaRemote, working through macOS 26 / Tahoe). Polls on demand and
/// publishes the latest snapshot; parsing is pure and unit-tested. See ND-3.
final class NowPlayingService: ObservableObject {

    static let shared = NowPlayingService()

    @Published private(set) var snapshot: NowPlayingSnapshot?

    /// Monotonically increasing token; each `refresh()` starts a new generation, so a
    /// stale callback from an abandoned fetch can't overwrite a fresher snapshot (F-L10).
    private var generation = 0
    /// The generation of the fetch currently in flight, or `nil` if none.
    private var inFlightGeneration: Int?

    /// Fetches the current track (the bridge calls back on the main queue).
    func refresh() {
        guard inFlightGeneration == nil else { return }
        generation += 1
        let fetchGeneration = generation
        inFlightGeneration = fetchGeneration
        JettyNowPlaying.fetch { [weak self] info in
            guard let self else { return }
            // Apply only if no newer fetch has started since; a callback from an
            // abandoned fetch must not overwrite a fresher snapshot (F-L10).
            guard fetchGeneration == self.generation else { return }
            self.inFlightGeneration = nil
            self.snapshot = Self.parse(info)
        }
        // Safety net: if a half-present private framework never delivers, invalidate
        // this fetch so future refreshes aren't blocked forever (H17). Guarded by the
        // generation so it never clears a newer fetch's in-flight state.
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            guard let self else { return }
            if self.inFlightGeneration == fetchGeneration {
                self.inFlightGeneration = nil
                self.generation += 1   // reject a callback that arrives after timeout
            }
        }
    }

    /// Builds a snapshot from the legacy-keyed MediaRemote dictionary. Pure.
    static func parse(_ info: [String: Any]?) -> NowPlayingSnapshot? {
        guard let info,
              let title = info["kMRMediaRemoteNowPlayingInfoTitle"] as? String,
              !title.isEmpty else { return nil }
        let artist = info["kMRMediaRemoteNowPlayingInfoArtist"] as? String
        let rate = (info["kMRMediaRemoteNowPlayingInfoPlaybackRate"] as? NSNumber)?.doubleValue ?? 0
        return NowPlayingSnapshot(title: title,
                                  artist: (artist?.isEmpty == false) ? artist : nil,
                                  isPlaying: rate > 0)
    }
}
