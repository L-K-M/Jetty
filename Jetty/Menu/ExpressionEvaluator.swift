import Foundation

/// A tiny, dependency-free arithmetic evaluator for the Jetty Menu's inline
/// calculator (improvement ND-1). It recognizes expressions like `2+2`,
/// `(12+3)/4`, `2^10`, `200*15%`, `899-15%`, and `-5 * 3`, evaluates them with
/// correct precedence, and formats the result.
///
/// Pure and fully unit-tested — no UI, no global state. A recursive-descent
/// parser (rather than `NSExpression`) keeps it deterministic: anything that
/// isn't a well-formed expression simply returns `nil`, so a normal app-name
/// query never shows a bogus result. Because the evaluator runs on the main
/// thread on every keystroke, its recursion is bounded — inputs longer than
/// 256 characters or nested deeper than 64 levels return `nil`, and the
/// unary-sign chain is folded iteratively, so pasted pathological input fails
/// cleanly instead of overflowing the stack (FAB-B9).
///
/// Grammar (precedence low → high):
/// ```
/// expr    := term (('+' | '-') term)*
/// term    := factor (('*' | '/') factor)*    // a '(' right after a factor is an implicit '*'
/// factor  := ('+' | '-')* postfix ('^' factor)?   // unary sign looser than ^,
///                                                  // ^ right-associative
/// postfix := primary ('%')*           // trailing percent → × 0.01
/// primary := number | '(' expr ')'
/// ```
/// A leading unary minus binds *looser* than `^`, so `-2^2` is `-(2^2) = -4` —
/// matching Spotlight, Google, Python, and Wolfram (Excel is the lone exception).
/// The exponent still parses as a `factor`, so `2^-2 = 0.25` keeps working.
/// Percent follows the desk-calculator/Spotlight convention: a bare `Y%` on the
/// right of `+`/`-` means Y percent *of the left value* (`899 - 15%` = 764.15),
/// while `*`/`/` keep the plain ×0.01 reading (`200*15%` = 30) (FAB-B10).
/// A parenthesized group directly after a factor multiplies implicitly, so
/// `2(3+4)` = 14 and `(1+2)(3+4)` = 21 (FAB-D19).
enum ExpressionEvaluator {

    /// A successfully evaluated expression: the (trimmed) input and its formatted value.
    struct Result: Equatable {
        let expression: String
        let value: String
    }

    /// Evaluates `input`, returning a formatted result only when it is a
    /// well-formed arithmetic expression that contains at least one digit **and**
    /// one operator (so plain searches like "Safari" and bare numbers are
    /// ignored). Returns `nil` for anything else, division by zero, a
    /// non-finite result, or input longer than 256 characters (a pasted wall of
    /// text is never a launcher calculation, and rejecting it up front keeps the
    /// per-keystroke parse bounded — FAB-B9).
    static func evaluate(_ input: String) -> Result? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              trimmed.count <= maxInputLength,
              trimmed.contains(where: { $0.isNumber }),
              trimmed.contains(where: { Self.operatorCharacters.contains($0) })
        else { return nil }

        guard let tokens = tokenize(trimmed) else { return nil }
        var parser = Parser(tokens: tokens)
        guard let value = parser.parseExpression(), parser.isAtEnd, value.isFinite else { return nil }
        return Result(expression: trimmed, value: format(value))
    }

    /// Characters that mark a query as "probably math". `×`/`÷` are accepted as
    /// aliases for `*`/`/`, and `−` (U+2212, the typographic minus that math copied
    /// from web pages / PDFs / the Character Viewer produces) as an alias for `-`, so
    /// the on-screen and pasted glyphs work too.
    private static let operatorCharacters: Set<Character> = ["+", "-", "*", "/", "^", "%", "×", "÷", "−"]

    /// Inputs longer than this are rejected before tokenizing (FAB-B9).
    private static let maxInputLength = 256

    // MARK: Tokenizing

    private enum Token: Equatable {
        case number(Double)
        case plus, minus, times, divide, power, percent
        case lparen, rparen
    }

    private static func tokenize(_ s: String) -> [Token]? {
        var tokens: [Token] = []
        let chars = Array(s)
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if c.isWhitespace { i += 1; continue }
            switch c {
            case "+": tokens.append(.plus); i += 1
            case "-", "−": tokens.append(.minus); i += 1
            case "*", "×": tokens.append(.times); i += 1
            case "/", "÷": tokens.append(.divide); i += 1
            case "^": tokens.append(.power); i += 1
            case "%": tokens.append(.percent); i += 1
            case "(": tokens.append(.lparen); i += 1
            case ")": tokens.append(.rparen); i += 1
            default:
                guard c.isNumber || c == "." else { return nil }
                var j = i
                var seenDot = false
                while j < chars.count, chars[j].isNumber || (chars[j] == "." && !seenDot) {
                    if chars[j] == "." { seenDot = true }
                    j += 1
                }
                guard let value = Double(String(chars[i..<j])) else { return nil }
                tokens.append(.number(value))
                i = j
            }
        }
        return tokens.isEmpty ? nil : tokens
    }

    // MARK: Parsing / evaluation

    private struct Parser {
        let tokens: [Token]
        var pos = 0
        var depth = 0

        /// Recursion is capped so deeply nested input (`((((…`) fails cleanly
        /// instead of overflowing the stack (FAB-B9). 64 levels is far beyond
        /// anything a person types into a launcher.
        private static let maxDepth = 64

        var isAtEnd: Bool { pos >= tokens.count }
        func peek() -> Token? { pos < tokens.count ? tokens[pos] : nil }

        mutating func parseExpression() -> Double? {
            depth += 1
            defer { depth -= 1 }
            guard depth <= Self.maxDepth else { return nil }
            guard let first = parseTerm() else { return nil }
            var value = first.value
            while let t = peek(), t == .plus || t == .minus {
                pos += 1
                guard let term = parseTerm() else { return nil }
                // `X + Y%` / `X - Y%` mean "X plus/minus Y percent *of X*" — the
                // desk-calculator/Spotlight/Google convention (FAB-B10). `*` and
                // `/` keep the plain ×0.01 reading, so `200*15%` is still 30.
                let rhs = term.isBarePercent ? value * term.value : term.value
                value = (t == .plus) ? value + rhs : value - rhs
            }
            return value
        }

        mutating func parseTerm() -> (value: Double, isBarePercent: Bool)? {
            guard let first = parseFactor() else { return nil }
            var value = first.value
            var isBarePercent = first.isBarePercent
            // A `(` directly after a factor is implicit multiplication, so
            // `2(3+4)` = 14 and `(1+2)(3+4)` = 21 (FAB-D19). The `(` is left in
            // place for `parseFactor` to consume as a primary.
            while let t = peek(), t == .times || t == .divide || t == .lparen {
                if t != .lparen { pos += 1 }
                guard let rhs = parseFactor() else { return nil }
                isBarePercent = false
                if t == .divide {
                    guard rhs.value != 0 else { return nil }
                    value /= rhs.value
                } else {
                    value *= rhs.value
                }
            }
            return (value, isBarePercent)
        }

        mutating func parseFactor() -> (value: Double, isBarePercent: Bool)? {
            depth += 1
            defer { depth -= 1 }
            guard depth <= Self.maxDepth else { return nil }
            // A leading unary sign binds looser than `^`, so `-2^2` == `-(2^2)` == -4.
            // The sign chain is folded iteratively so a pasted wall of `-` can't
            // recurse the stack away (FAB-B9).
            var negate = false
            while let t = peek(), t == .plus || t == .minus {
                pos += 1
                if t == .minus { negate.toggle() }
            }
            guard let operand = parsePostfix() else { return nil }
            var value = operand.value
            var isBarePercent = operand.isBarePercent
            if let t = peek(), t == .power {
                pos += 1
                // Right-associative, and the exponent is itself a factor so `2^-2` works.
                guard let exponent = parseFactor() else { return nil }
                value = pow(value, exponent.value)
                isBarePercent = false
            }
            return (negate ? -value : value, isBarePercent)
        }

        mutating func parsePostfix() -> (value: Double, isBarePercent: Bool)? {
            guard var value = parsePrimary() else { return nil }
            var isBarePercent = false
            while let t = peek(), t == .percent {
                pos += 1
                value *= 0.01
                isBarePercent = true
            }
            return (value, isBarePercent)
        }

        mutating func parsePrimary() -> Double? {
            guard let token = peek() else { return nil }
            switch token {
            case .number(let value):
                pos += 1
                return value
            case .lparen:
                pos += 1
                guard let value = parseExpression() else { return nil }
                guard let next = peek(), next == .rparen else { return nil }
                pos += 1
                return value
            default:
                return nil
            }
        }
    }

    // MARK: Formatting

    /// Formats a finite result: whole numbers print without a decimal, otherwise
    /// up to 10 fractional digits with trailing zeros trimmed. A non-zero value
    /// too small for that fixed fraction budget falls back to significant-digit
    /// (scientific) notation — `2^-40` shows `9.094947018e-13`, never a
    /// confidently wrong `0` (FAB-B8). Huge magnitudes switch to significant
    /// digits too — `2^700` would otherwise print ~200 meaningless binary64
    /// digits.
    static func format(_ value: Double) -> String {
        if value == value.rounded(), abs(value) < 1e15 {
            return String(Int64(value))
        }
        if abs(value) >= 1e15 { return scientificString(value, significantDigits: 10) }
        var s = String(format: "%.10f", value)
        while s.contains("."), s.hasSuffix("0") { s.removeLast() }
        if s.hasSuffix(".") { s.removeLast() }
        if value != 0, s == "0" || s == "-0" {
            return scientificString(value, significantDigits: 10)
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
}
