import Foundation

/// Live currency conversion for the Jetty Menu command bar (ND-9). Fetches rates
/// (base USD) from Frankfurter (frankfurter.app — free, no key, ECB data), caches
/// them for the session, and converts from the cache so the menu stays synchronous.
/// Parsing is pure and unit-tested.
final class CurrencyService: ObservableObject {

    static let shared = CurrencyService()

    /// Units of each currency per 1 USD (e.g. `["EUR": 0.92]`); always includes USD = 1.
    @Published private(set) var rates: [String: Double] = [:]

    private var lastFetch: Date?
    private var inFlight = false

    /// Loads rates if missing or older than 6 hours.
    func ensureFresh() {
        if !rates.isEmpty, let last = lastFetch, Date().timeIntervalSince(last) < 6 * 3600 { return }
        guard !inFlight else { return }
        fetch()
    }

    private func fetch() {
        guard let url = URL(string: "https://api.frankfurter.app/latest?from=USD") else { return }
        inFlight = true
        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            let parsed = Self.parseRates(data)
            DispatchQueue.main.async {
                self?.inFlight = false
                guard let parsed else { return }
                self?.rates = parsed
                self?.lastFetch = Date()
            }
        }.resume()
    }

    func known(_ code: String) -> Bool {
        let c = code.uppercased()
        return c == "USD" || rates[c] != nil
    }

    /// Converts `amount` from one currency to another using the cached rates.
    func convert(amount: Double, from: String, to: String) -> Double? {
        Self.convert(amount: amount, from: from, to: to, rates: rates)
    }

    /// Pure conversion over an explicit rate table (per-USD; USD implied = 1). Tested.
    static func convert(amount: Double, from: String, to: String, rates: [String: Double]) -> Double? {
        func rate(_ code: String) -> Double? {
            let c = code.uppercased()
            return c == "USD" ? 1.0 : rates[c]
        }
        guard let rf = rate(from), let rt = rate(to) else { return nil }
        return amount / rf * rt
    }

    // MARK: Pure parsing

    /// Parses a Frankfurter `latest` payload into `{CODE: perUSD}` (incl. USD = 1).
    static func parseRates(_ data: Data?) -> [String: Double]? {
        guard let data,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rates = json["rates"] as? [String: Any] else { return nil }
        var out: [String: Double] = ["USD": 1.0]
        for (code, value) in rates {
            if let number = (value as? NSNumber)?.doubleValue { out[code.uppercased()] = number }
        }
        return out.count > 1 ? out : nil
    }

    /// Parses "<amount> <CCY> in|to <CCY>" into its parts (uppercased codes). Pure.
    static func parseQuery(_ input: String) -> (amount: Double, from: String, to: String)? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let range = NSRange(trimmed.startIndex..., in: trimmed)
        guard let match = queryRegex.firstMatch(in: trimmed, range: range) else { return nil }
        func group(_ i: Int) -> String? { Range(match.range(at: i), in: trimmed).map { String(trimmed[$0]) } }
        guard let amount = group(1).flatMap(Double.init),
              let from = group(2), let to = group(3) else { return nil }
        return (amount, from.uppercased(), to.uppercased())
    }

    private static let queryRegex = try! NSRegularExpression(
        pattern: #"^(-?\d+(?:\.\d+)?)\s*([a-zA-Z]{3})\s+(?:in|to)\s+([a-zA-Z]{3})$"#,
        options: [.caseInsensitive])
}
