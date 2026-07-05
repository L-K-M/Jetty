import SwiftUI

/// A weather tile (ND-3): a conditions glyph plus the current temperature for the
/// user-set coordinates, refreshed (at most) every 15 minutes from Open-Meteo. Shows
/// a "set location" hint until coordinates are configured, and a spinner until the
/// first result lands.
struct WeatherWidgetView: View {
    @ObservedObject var preferences: Preferences
    @ObservedObject private var service = WeatherService.shared
    var height: CGFloat
    var tint: Color

    var body: some View {
        // Tick every 15 minutes normally, but every minute while the last fetch failed,
        // so a transient failure heals after ~60 s (WeatherService's failure backoff)
        // instead of sticking for the full window (FAB-B19).
        TimelineView(.periodic(from: .now, by: service.isOffline ? 60 : 900)) { context in
            content
                .onChange(of: context.date) { _ in refresh() }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onAppear { refresh() }
        .onChange(of: preferences.weatherLatitude) { _ in refresh() }
        .onChange(of: preferences.weatherLongitude) { _ in refresh() }
        .onChange(of: preferences.weatherUseCelsius) { _ in refresh() }
        .help(helpText)
    }

    private var hasLocation: Bool {
        preferences.weatherLatitude != 0 || preferences.weatherLongitude != 0
    }

    /// One computed tooltip — nesting a second `.help` on the offline glyph inside the
    /// outer one left the winner undefined (FAB-B19). Matches the tap behavior in
    /// `DockController`: while unavailable, a tap retries the fetch.
    private var helpText: String {
        service.isUnavailable(latitude: preferences.weatherLatitude,
                              longitude: preferences.weatherLongitude,
                              celsius: preferences.weatherUseCelsius)
            ? "Weather unavailable — tap to retry"
            : "Weather"
    }

    @ViewBuilder
    private var content: some View {
        let key = WeatherService.key(latitude: preferences.weatherLatitude,
                                     longitude: preferences.weatherLongitude,
                                     celsius: preferences.weatherUseCelsius)
        if !hasLocation {
            VStack(spacing: 2) {
                Image(systemName: "location.slash").font(.system(size: max(11, height * 0.3)))
                    .foregroundStyle(.secondary)
                Text("Set").font(.system(size: max(8, height * 0.18), weight: .medium))
                    .foregroundStyle(.secondary)
            }
        } else if let snap = service.snapshot, snap.key == key {
            VStack(spacing: 1) {
                Image(systemName: WeatherService.symbol(forCode: snap.code))
                    .symbolRenderingMode(.multicolor)
                    .font(.system(size: max(18, height * 0.5)))
                    .foregroundStyle(tint)
                Text("\(Int(snap.temperature.rounded()))°")
                    .font(.system(size: max(9, height * 0.2), weight: .semibold, design: .rounded))
                    .monospacedDigit()
            }
        } else if service.isOffline {
            // A fetch failed and we have no reading for this location — show an offline
            // glyph instead of an eternal spinner (H15).
            VStack(spacing: 2) {
                Image(systemName: "cloud.slash").font(.system(size: max(11, height * 0.3)))
                    .foregroundStyle(.secondary)
                Text("—").font(.system(size: max(8, height * 0.18), weight: .medium))
                    .foregroundStyle(.secondary)
            }
        } else {
            ProgressView().controlSize(.small)
        }
    }

    private func refresh() {
        service.refreshIfStale(latitude: preferences.weatherLatitude,
                               longitude: preferences.weatherLongitude,
                               celsius: preferences.weatherUseCelsius)
    }
}
