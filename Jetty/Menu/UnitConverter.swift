import Foundation

/// A tiny natural-language unit converter for the Jetty Menu command bar (ND-9):
/// turns queries like `10 km in miles`, `100 f to c`, `5 kg in lb`, or `2 gb to mb`
/// into a formatted result. Pure and unit-tested; anything that isn't a recognized
/// "<number> <unit> in|to <unit>" returns `nil`, so ordinary searches are untouched.
enum UnitConverter {

    struct Result: Equatable { let value: String }

    /// Converts `input`, or returns `nil` if it isn't a same-dimension unit query.
    static func convert(_ input: String) -> Result? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let range = NSRange(trimmed.startIndex..., in: trimmed)
        guard let match = regex.firstMatch(in: trimmed, range: range) else { return nil }

        func group(_ i: Int) -> String? {
            Range(match.range(at: i), in: trimmed).map { String(trimmed[$0]) }
        }
        guard let numberString = group(1), let value = Double(numberString),
              let fromKey = group(2)?.lowercased(), let toKey = group(3)?.lowercased(),
              let from = units[fromKey], let to = units[toKey], from.dim == to.dim else { return nil }

        let converted = Measurement(value: value, unit: from.unit).converted(to: to.unit)
        return Result(value: "\(format(converted.value)) \(to.label)")
    }

    // MARK: Parsing

    private static let regex: NSRegularExpression = {
        // <number> <unit>  (in|to)  <unit>. The unit class includes `"` so the inch
        // alias is reachable (M41).
        let pattern = #"^(-?\d+(?:\.\d+)?)\s*([a-zA-Z°"]+)\s+(?:in|to)\s+([a-zA-Z°"]+)$"#
        // Pattern is a compile-time constant, so this never fails.
        return try! NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
    }()

    /// Formats a converted value: whole numbers print plainly, else up to 4 decimals
    /// with trailing zeros trimmed. A non-zero value too small for the 4-decimal
    /// budget falls back to significant-digit (scientific) notation — `1 mm to km`
    /// shows `1e-6 km`, never a confidently wrong `0 km` (FAB-B8).
    static func format(_ value: Double) -> String {
        if value == value.rounded(), abs(value) < 1e12 { return String(Int64(value)) }
        var s = String(format: "%.4f", value)
        while s.contains("."), s.hasSuffix("0") { s.removeLast() }
        if s.hasSuffix(".") { s.removeLast() }
        if value != 0, s == "0" || s == "-0" {
            return scientificString(value, significantDigits: 4)
        }
        return s
    }

    /// `%g` significant-digit formatting with the exponent tidied
    /// (`1e-06` → `1e-6`), used when a non-zero result underflows the fixed
    /// decimal budget (FAB-B8).
    private static func scientificString(_ value: Double, significantDigits: Int) -> String {
        var s = String(format: "%.\(significantDigits)g", value)
        if let e = s.firstIndex(of: "e") {
            let mantissa = String(s[..<e])
            var exponent = String(s[s.index(after: e)...])
            var sign = ""
            if exponent.hasPrefix("+") {
                exponent.removeFirst()
            } else if exponent.hasPrefix("-") {
                sign = "-"
                exponent.removeFirst()
            }
            while exponent.count > 1, exponent.hasPrefix("0") { exponent.removeFirst() }
            s = mantissa + "e" + sign + exponent
        }
        return s
    }

    // MARK: Unit registry

    /// alias → (dimension tag, Foundation unit, display label). `in` doubles as the
    /// separator, but the anchored regex captures the target unit as a distinct group,
    /// so registering `in` as an inch alias makes `10 m to in` work (M41).
    private static let units: [String: (dim: String, unit: Dimension, label: String)] = {
        var map: [String: (String, Dimension, String)] = [:]
        func add(_ aliases: [String], _ dim: String, _ unit: Dimension, _ label: String) {
            for a in aliases { map[a] = (dim, unit, label) }
        }
        // Length
        add(["km", "kilometer", "kilometers", "kilometre", "kilometres"], "len", UnitLength.kilometers, "km")
        add(["m", "meter", "meters", "metre", "metres"], "len", UnitLength.meters, "m")
        add(["cm", "centimeter", "centimeters"], "len", UnitLength.centimeters, "cm")
        add(["mm", "millimeter", "millimeters"], "len", UnitLength.millimeters, "mm")
        add(["mi", "mile", "miles"], "len", UnitLength.miles, "mi")
        add(["ft", "foot", "feet"], "len", UnitLength.feet, "ft")
        add(["inch", "inches", "\"", "in"], "len", UnitLength.inches, "in")
        add(["yd", "yard", "yards"], "len", UnitLength.yards, "yd")
        // Mass
        add(["kg", "kilogram", "kilograms"], "mass", UnitMass.kilograms, "kg")
        add(["g", "gram", "grams"], "mass", UnitMass.grams, "g")
        add(["mg", "milligram", "milligrams"], "mass", UnitMass.milligrams, "mg")
        add(["lb", "lbs", "pound", "pounds"], "mass", UnitMass.pounds, "lb")
        add(["oz", "ounce", "ounces"], "mass", UnitMass.ounces, "oz")
        // Temperature
        add(["c", "°c", "celsius", "centigrade"], "temp", UnitTemperature.celsius, "°C")
        add(["f", "°f", "fahrenheit"], "temp", UnitTemperature.fahrenheit, "°F")
        add(["k", "kelvin"], "temp", UnitTemperature.kelvin, "K")
        // Volume
        add(["l", "liter", "liters", "litre", "litres"], "vol", UnitVolume.liters, "L")
        add(["ml", "milliliter", "milliliters"], "vol", UnitVolume.milliliters, "mL")
        add(["gal", "gallon", "gallons"], "vol", UnitVolume.gallons, "gal")
        // Speed
        add(["kmh", "kph"], "speed", UnitSpeed.kilometersPerHour, "km/h")
        add(["mph"], "speed", UnitSpeed.milesPerHour, "mph")
        // Data
        add(["kb", "kilobyte", "kilobytes"], "data", UnitInformationStorage.kilobytes, "KB")
        add(["mb", "megabyte", "megabytes"], "data", UnitInformationStorage.megabytes, "MB")
        add(["gb", "gigabyte", "gigabytes"], "data", UnitInformationStorage.gigabytes, "GB")
        add(["tb", "terabyte", "terabytes"], "data", UnitInformationStorage.terabytes, "TB")
        return map
    }()
}
