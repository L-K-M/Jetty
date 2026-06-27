import SwiftUI

/// Settings for the live info-widget tiles (ND-3): the clock, world clock, Pomodoro,
/// and weather. Add the tiles themselves from Items ▸ Add ▸ Info Widget.
struct WidgetsView: View {
    @ObservedObject var preferences: Preferences

    private var zoneIdentifiers: [String] { TimeZone.knownTimeZoneIdentifiers.sorted() }

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
                    ForEach(zoneIdentifiers, id: \.self) { Text($0).tag($0) }
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
