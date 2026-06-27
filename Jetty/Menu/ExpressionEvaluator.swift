import Foundation

/// A tiny, dependency-free arithmetic evaluator for the Jetty Menu's inline
/// calculator (improvement ND-1). It recognizes expressions like `2+2`,
/// `(12+3)/4`, `2^10`, `200*15%`, and `-5 * 3`, evaluates them with correct
/// precedence, and formats the result.
///
/// Pure and fully unit-tested — no UI, no global state. A recursive-descent
/// parser (rather than `NSExpression`) keeps it deterministic and crash-proof on
/// malformed input: anything that isn't a well-formed expression simply returns
/// `nil`, so a normal app-name query never shows a bogus result.
///
/// Grammar (precedence low → high):
/// ```
/// expr    := term (('+' | '-') term)*
/// term    := factor (('*' | '/') factor)*
/// factor  := unary ('^' factor)?      // right-associative
/// unary   := ('+' | '-') unary | postfix
/// postfix := primary ('%')*           // trailing percent → × 0.01
/// primary := number | '(' expr ')'
/// ```
enum ExpressionEvaluator {

    /// A successfully evaluated expression: the (trimmed) input and its formatted value.
    struct Result: Equatable {
        let expression: String
        let value: String
    }

    /// Evaluates `input`, returning a formatted result only when it is a
    /// well-formed arithmetic expression that contains at least one digit **and**
    /// one operator (so plain searches like "Safari" and bare numbers are
    /// ignored). Returns `nil` for anything else, division by zero, or a
    /// non-finite result.
    static func evaluate(_ input: String) -> Result? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              trimmed.contains(where: { $0.isNumber }),
              trimmed.contains(where: { Self.operatorCharacters.contains($0) })
        else { return nil }

        guard let tokens = tokenize(trimmed) else { return nil }
        var parser = Parser(tokens: tokens)
        guard let value = parser.parseExpression(), parser.isAtEnd, value.isFinite else { return nil }
        return Result(expression: trimmed, value: format(value))
    }

    /// Characters that mark a query as "probably math". `×`/`÷` are accepted as
    /// aliases for `*`/`/` so the on-screen multiply/divide glyphs work too.
    private static let operatorCharacters: Set<Character> = ["+", "-", "*", "/", "^", "%", "×", "÷"]

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
            case "-": tokens.append(.minus); i += 1
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

        var isAtEnd: Bool { pos >= tokens.count }
        func peek() -> Token? { pos < tokens.count ? tokens[pos] : nil }

        mutating func parseExpression() -> Double? {
            guard var value = parseTerm() else { return nil }
            while let t = peek(), t == .plus || t == .minus {
                pos += 1
                guard let rhs = parseTerm() else { return nil }
                value = (t == .plus) ? value + rhs : value - rhs
            }
            return value
        }

        mutating func parseTerm() -> Double? {
            guard var value = parseFactor() else { return nil }
            while let t = peek(), t == .times || t == .divide {
                pos += 1
                guard let rhs = parseFactor() else { return nil }
                if t == .divide {
                    guard rhs != 0 else { return nil }
                    value /= rhs
                } else {
                    value *= rhs
                }
            }
            return value
        }

        mutating func parseFactor() -> Double? {
            guard let base = parseUnary() else { return nil }
            if let t = peek(), t == .power {
                pos += 1
                guard let exponent = parseFactor() else { return nil }   // right-associative
                return pow(base, exponent)
            }
            return base
        }

        mutating func parseUnary() -> Double? {
            if let t = peek(), t == .plus || t == .minus {
                pos += 1
                guard let value = parseUnary() else { return nil }
                return t == .minus ? -value : value
            }
            return parsePostfix()
        }

        mutating func parsePostfix() -> Double? {
            guard var value = parsePrimary() else { return nil }
            while let t = peek(), t == .percent {
                pos += 1
                value *= 0.01
            }
            return value
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
    /// up to 10 fractional digits with trailing zeros trimmed.
    static func format(_ value: Double) -> String {
        if value == value.rounded(), abs(value) < 1e15 {
            return String(Int64(value))
        }
        var s = String(format: "%.10f", value)
        while s.contains("."), s.hasSuffix("0") { s.removeLast() }
        if s.hasSuffix(".") { s.removeLast() }
        return s
    }
}
