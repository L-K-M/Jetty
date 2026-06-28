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
        TimelineView(.periodic(from: .now, by: 900)) { context in
            content
                .onChange(of: context.date) { _ in refresh() }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onAppear { refresh() }
        .onChange(of: preferences.weatherLatitude) { _ in refresh() }
        .onChange(of: preferences.weatherLongitude) { _ in refresh() }
        .onChange(of: preferences.weatherUseCelsius) { _ in refresh() }
        .help("Weather")
    }

    private var hasLocation: Bool {
        preferences.weatherLatitude != 0 || preferences.weatherLongitude != 0
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
