import Foundation

/// A current-conditions snapshot for the weather tile.
struct WeatherSnapshot: Equatable {
    let temperature: Double
    let code: Int          // WMO weather-interpretation code
    let celsius: Bool
}

/// Fetches current weather from Open-Meteo (free, no API key, no account). Caches the
/// last result and only refetches when the location/unit changes or the data is
/// older than 15 minutes — so the tile is cheap to render. Network only; no location
/// permission (the user supplies coordinates). See ND-3.
final class WeatherService: ObservableObject {

    static let shared = WeatherService()

    @Published private(set) var snapshot: WeatherSnapshot?

    private var inFlight = false
    private var lastKey: String?
    private var lastFetch: Date?

    /// Refreshes if a location is set and the cache is stale or its key changed.
    func refreshIfStale(latitude: Double, longitude: Double, celsius: Bool) {
        guard latitude != 0 || longitude != 0 else { return }
        let key = "\(latitude),\(longitude),\(celsius)"
        if key == lastKey, let last = lastFetch, Date().timeIntervalSince(last) < 15 * 60 { return }
        guard !inFlight else { return }
        fetch(latitude: latitude, longitude: longitude, celsius: celsius, key: key)
    }

    private func fetch(latitude: Double, longitude: Double, celsius: Bool, key: String) {
        let unit = celsius ? "celsius" : "fahrenheit"
        let string = "https://api.open-meteo.com/v1/forecast?latitude=\(latitude)&longitude=\(longitude)"
            + "&current=temperature_2m,weather_code&temperature_unit=\(unit)"
        guard let url = URL(string: string) else { return }
        inFlight = true
        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            let parsed = Self.parse(data, celsius: celsius)
            DispatchQueue.main.async {
                self?.inFlight = false
                guard let parsed else { return }
                self?.snapshot = parsed
                self?.lastKey = key
                self?.lastFetch = Date()
            }
        }.resume()
    }

    /// Parses an Open-Meteo response body into a snapshot (pure aside from JSON).
    static func parse(_ data: Data?, celsius: Bool) -> WeatherSnapshot? {
        guard let data,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let current = json["current"] as? [String: Any],
              let temp = (current["temperature_2m"] as? NSNumber)?.doubleValue else { return nil }
        let code = (current["weather_code"] as? NSNumber)?.intValue ?? 0
        return WeatherSnapshot(temperature: temp, code: code, celsius: celsius)
    }

    /// WMO weather-interpretation code → SF Symbol. Pure, unit-tested.
    static func symbol(forCode code: Int) -> String {
        switch code {
        case 0:        return "sun.max.fill"
        case 1, 2:     return "cloud.sun.fill"
        case 3:        return "cloud.fill"
        case 45, 48:   return "cloud.fog.fill"
        case 51...57:  return "cloud.drizzle.fill"
        case 61...67:  return "cloud.rain.fill"
        case 71...77:  return "cloud.snow.fill"
        case 80...82:  return "cloud.heavyrain.fill"
        case 85, 86:   return "cloud.snow.fill"
        case 95...99:  return "cloud.bolt.rain.fill"
        default:       return "cloud.fill"
        }
    }
}
