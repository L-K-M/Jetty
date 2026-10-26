import SwiftUI

/// The linked credit Open-Meteo's CC BY 4.0 terms ask for next to its data: "Weather
/// data by Open-Meteo.com" plus a link to the licence. Shown in the Weather settings
/// and the About pane.
struct WeatherAttributionLinks: View {
    var body: some View {
        HStack(spacing: 4) {
            Link(WeatherService.attribution, destination: WeatherService.attributionURL)
            Text("·").foregroundStyle(.secondary)
            Link(WeatherService.dataLicense, destination: WeatherService.dataLicenseURL)
        }
        .font(.caption)
    }
}
