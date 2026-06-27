import SwiftUI

/// A now-playing tile (ND-3): a play/pause glyph plus the current track title and
/// artist, refreshed every few seconds. Falls back to a music-note glyph when
/// nothing is playing (or MediaRemote yields nothing).
struct NowPlayingWidgetView: View {
    @ObservedObject private var service = NowPlayingService.shared
    var height: CGFloat
    var tint: Color

    var body: some View {
        TimelineView(.periodic(from: .now, by: 5)) { context in
            content.onChange(of: context.date) { _ in service.refresh() }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onAppear { service.refresh() }
        .help("Now playing")
    }

    @ViewBuilder
    private var content: some View {
        if let snap = service.snapshot {
            HStack(spacing: 6) {
                Image(systemName: snap.isPlaying ? "play.fill" : "pause.fill")
                    .font(.system(size: max(9, height * 0.22)))
                    .foregroundStyle(tint)
                VStack(alignment: .leading, spacing: 0) {
                    Text(snap.title)
                        .font(.system(size: max(9, height * 0.2), weight: .semibold))
                        .lineLimit(1).truncationMode(.tail)
                    if let artist = snap.artist {
                        Text(artist)
                            .font(.system(size: max(7, height * 0.16)))
                            .foregroundStyle(.secondary).lineLimit(1).truncationMode(.tail)
                    }
                }
            }
            .padding(.horizontal, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            Image(systemName: "music.note")
                .font(.system(size: max(13, height * 0.34)))
                .foregroundStyle(.secondary)
        }
    }
}
