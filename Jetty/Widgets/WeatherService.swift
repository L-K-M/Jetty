import Foundation

/// A current-conditions snapshot for the weather tile.
struct WeatherSnapshot: Equatable {
    let temperature: Double
    let code: Int          // WMO weather-interpretation code
    let celsius: Bool
    let key: String

    init(temperature: Double, code: Int, celsius: Bool, key: String = "") {
        self.temperature = temperature
        self.code = code
        self.celsius = celsius
        self.key = key
    }
}

/// Fetches current weather from Open-Meteo (free, no API key, no account). Caches the
/// last result and only refetches when the location/unit changes or the data is
/// older than 15 minutes — so the tile is cheap to render. Network only; no location
/// permission (the user supplies coordinates). See ND-3.
final class WeatherService: ObservableObject {

    static let shared = WeatherService()

    @Published private(set) var snapshot: WeatherSnapshot?
    /// True when the last fetch failed (offline, HTTP error, or unparseable). The tile
    /// shows an offline glyph (keeping any stale reading) rather than an eternal
    /// spinner (H15).
    @Published private(set) var isOffline = false

    private var inFlightKey: String?
    private var requestedKey: String?
    private var lastKey: String?
    private var lastFetch: Date?

    static func key(latitude: Double, longitude: Double, celsius: Bool) -> String {
        "\(latitude),\(longitude),\(celsius)"
    }

    /// Refreshes if a location is set and the cache is stale or its key changed.
    func refreshIfStale(latitude: Double, longitude: Double, celsius: Bool) {
        guard latitude != 0 || longitude != 0 else { return }
        let key = Self.key(latitude: latitude, longitude: longitude, celsius: celsius)
        requestedKey = key
        // Deliberately do NOT clear `snapshot` here. The view only shows a snapshot whose
        // key matches the current one, so a stale-keyed snapshot is harmless — and keeping
        // it means flipping the unit/location back within the 15-minute freshness window
        // instantly re-displays the still-fresh reading instead of stranding a spinner
        // while the freshness gate below blocks a refetch (F-M5).
        if key == lastKey, let last = lastFetch, Date().timeIntervalSince(last) < 15 * 60,
           snapshot?.key == key { return }
        guard inFlightKey != key else { return }
        fetch(latitude: latitude, longitude: longitude, celsius: celsius, key: key)
    }

    private func fetch(latitude: Double, longitude: Double, celsius: Bool, key: String) {
        let unit = celsius ? "celsius" : "fahrenheit"
        let string = "https://api.open-meteo.com/v1/forecast?latitude=\(latitude)&longitude=\(longitude)"
            + "&current=temperature_2m,weather_code&temperature_unit=\(unit)"
        guard let url = URL(string: string) else { return }
        inFlightKey = key
        URLSession.shared.dataTask(with: url) { [weak self] data, response, error in
            // Honor transport errors and non-2xx responses instead of silently swallowing
            // them — otherwise a down network / API error left the tile spinning forever (H15).
            let httpOK = (response as? HTTPURLResponse).map { (200..<300).contains($0.statusCode) } ?? true
            let parsed = (error == nil && httpOK) ? Self.parse(data, celsius: celsius, key: key) : nil
            DispatchQueue.main.async {
                guard let self else { return }
                if self.inFlightKey == key { self.inFlightKey = nil }
                guard self.requestedKey == key else { return }
                if let parsed {
                    self.snapshot = parsed
                    self.lastKey = key
                    self.lastFetch = Date()
                    self.isOffline = false
                } else {
                    // Keep any stale snapshot; just flag offline so the view can react.
                    self.isOffline = true
                }
            }
        }.resume()
    }

    /// Parses an Open-Meteo response body into a snapshot (pure aside from JSON).
    static func parse(_ data: Data?, celsius: Bool, key: String = "") -> WeatherSnapshot? {
        guard let data,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let current = json["current"] as? [String: Any],
              let temp = (current["temperature_2m"] as? NSNumber)?.doubleValue else { return nil }
        let code = (current["weather_code"] as? NSNumber)?.intValue ?? 0
        return WeatherSnapshot(temperature: temp, code: code, celsius: celsius, key: key)
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
