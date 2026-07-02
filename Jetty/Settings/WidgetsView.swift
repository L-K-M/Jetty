import SwiftUI

/// Settings for the live info-widget tiles (ND-3): the clock, world clock, Pomodoro,
/// and weather. Add the tiles themselves from Items ▸ Add ▸ Info Widget.
struct WidgetsView: View {
    @ObservedObject var preferences: Preferences

    // Sorted once — re-sorting ~600 zone ids on every Settings render was pure waste (F-P5).
    private static let zoneIdentifiers: [String] = TimeZone.knownTimeZoneIdentifiers.sorted()

    var body: some View {
        Form {
            Section("Clock") {
                Toggle("Analog face", isOn: $preferences.clockAnalog)
                if !preferences.clockAnalog {
                    Toggle("Show date", isOn: $preferences.clockShowDate)
                    Toggle("Show weekday", isOn: $preferences.clockShowWeekday)
                    Toggle("24-hour time", isOn: $preferences.clockUse24Hour)
                }
                Toggle("Show seconds", isOn: $preferences.clockShowSeconds)
            }

            Section("World Clock") {
                Picker("Time zone", selection: $preferences.worldClockTimeZone) {
                    ForEach(Self.zoneIdentifiers, id: \.self) { Text($0).tag($0) }
                }
                Text("Shows the time in another zone. The 12/24-hour and seconds options above apply here too.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Pomodoro") {
                Stepper(value: $preferences.pomodoroMinutes, in: 1...180, step: 1) {
                    Text("Session length: \(Int(preferences.pomodoroMinutes)) min")
                }
                Text("Click the Pomodoro tile to start or pause; right-click to reset.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("System Monitor") {
                Picker("Style", selection: $preferences.systemMonitorStyle) {
                    ForEach(SystemMonitorStyle.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                if preferences.systemMonitorStyle == .graph {
                    Toggle("Include network activity", isOn: $preferences.systemMonitorShowNetwork)
                }
                Text(preferences.systemMonitorStyle == .graph
                     ? "Plots CPU and memory (and, optionally, total network throughput) over the last couple of minutes. The widget is permission-free."
                     : "Two slim gauges for CPU load and memory usage. Switch to Graph for a sparkline of the trend over time.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Weather") {
                HStack {
                    Text("Latitude")
                    Spacer()
                    TextField("0.0", value: $preferences.weatherLatitude, format: .number)
                        .frame(width: 100).multilineTextAlignment(.trailing)
                }
                HStack {
                    Text("Longitude")
                    Spacer()
                    TextField("0.0", value: $preferences.weatherLongitude, format: .number)
                        .frame(width: 100).multilineTextAlignment(.trailing)
                }
                Picker("Units", selection: $preferences.weatherUseCelsius) {
                    Text("Celsius").tag(true)
                    Text("Fahrenheit").tag(false)
                }
                .pickerStyle(.segmented)
                Text("Current conditions from Open-Meteo (no account or location permission needed). Enter your coordinates — for example San Francisco is 37.77, −122.42.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}
