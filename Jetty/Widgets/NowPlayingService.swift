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

    private var inFlight = false

    /// Fetches the current track (the bridge calls back on the main queue).
    func refresh() {
        guard !inFlight else { return }
        inFlight = true
        JettyNowPlaying.fetch { [weak self] info in
            self?.inFlight = false
            self?.snapshot = Self.parse(info)
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
