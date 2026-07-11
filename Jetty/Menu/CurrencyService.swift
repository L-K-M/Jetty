import Foundation

/// Live currency conversion for the Jetty Menu command bar (ND-9). Fetches rates
/// (base USD) from Frankfurter (frankfurter.app — free, no key, ECB data), caches
/// them for the session, and converts from the cache so the menu stays synchronous.
/// Parsing is pure and unit-tested.
final class CurrencyService: ObservableObject {

    enum FetchState: Equatable {
        case idle
        case loading
        case failed
    }

    static let shared = CurrencyService()

    /// Units of each currency per 1 USD (e.g. `["EUR": 0.92]`); always includes USD = 1.
    @Published private(set) var rates: [String: Double] = [:]
    @Published private(set) var fetchState: FetchState = .idle

    private var lastFetch: Date?

    /// Local ISO validation rejects arbitrary three-letter search tokens without
    /// coupling Jetty to a provider list that changes as currencies enter/leave ECB.
    private static let supportedCodes = Set(Locale.commonISOCurrencyCodes)
    private var retryAfter: Date?

    /// Loads rates if missing or older than 6 hours.
    func ensureFresh(force: Bool = false) {
        if !rates.isEmpty, let last = lastFetch, Date().timeIntervalSince(last) < 6 * 3600 { return }
        guard fetchState != .loading else { return }
        if !force, let retryAfter, retryAfter > Date() { return }
        fetch()
    }

    private func fetch() {
        guard let url = URL(string: "https://api.frankfurter.app/latest?from=USD") else { return }
        fetchState = .loading
        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            let parsed = Self.parseRates(data)
            DispatchQueue.main.async {
                guard let self else { return }
                guard let parsed else {
                    self.retryAfter = Date().addingTimeInterval(60)
                    self.fetchState = .failed
                    return
                }
                self.rates = parsed
                self.lastFetch = Date()
                self.retryAfter = nil
                self.fetchState = .idle
            }
        }.resume()
    }

    static func supports(_ code: String) -> Bool {
        supportedCodes.contains(code.uppercased())
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
        // Reject zero / non-finite rates so a malformed payload can't divide-by-zero
        // into `"inf EUR"` (M32).
        guard let rf = rate(from), let rt = rate(to),
              rf.isFinite, rt.isFinite, rf != 0, rt != 0 else { return nil }
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
            // Skip non-positive / non-finite rates so a bad payload can't poison `convert`
            // with a zero or NaN divisor (M32).
            if let number = (value as? NSNumber)?.doubleValue, number.isFinite, number > 0 {
                out[code.uppercased()] = number
            }
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
