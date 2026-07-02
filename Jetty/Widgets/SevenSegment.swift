import Foundation

/// The classic seven-segment display: which segments light up for each digit.
/// A pure lookup so the LCD clock face's digit shapes are unit-testable.
///
///       ┌─ a ─┐
///       f     b
///       ├─ g ─┤
///       e     c
///       └─ d ─┘
enum SevenSegment {

    struct Segments: OptionSet {
        let rawValue: Int
        static let a = Segments(rawValue: 1 << 0)
        static let b = Segments(rawValue: 1 << 1)
        static let c = Segments(rawValue: 1 << 2)
        static let d = Segments(rawValue: 1 << 3)
        static let e = Segments(rawValue: 1 << 4)
        static let f = Segments(rawValue: 1 << 5)
        static let g = Segments(rawValue: 1 << 6)
        static let all: Segments = [.a, .b, .c, .d, .e, .f, .g]
    }

    /// The lit segments for `digit`, or `nil` outside 0–9.
    static func segments(for digit: Int) -> Segments? {
        switch digit {
        case 0: return [.a, .b, .c, .d, .e, .f]
        case 1: return [.b, .c]
        case 2: return [.a, .b, .g, .e, .d]
        case 3: return [.a, .b, .g, .c, .d]
        case 4: return [.f, .g, .b, .c]
        case 5: return [.a, .f, .g, .c, .d]
        case 6: return [.a, .f, .g, .e, .d, .c]
        case 7: return [.a, .b, .c]
        case 8: return .all
        case 9: return [.a, .b, .c, .d, .f, .g]
        default: return nil
        }
    }
}
