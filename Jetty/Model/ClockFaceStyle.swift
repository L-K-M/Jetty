import Foundation

/// The look of the date/time dock tile — the plain text style, a retro
/// seven-segment LCD in a resin sports-watch case, or one of the analog dials
/// *inspired by* iconic watches (a clean station-style dial, the mid-90s
/// rainbow-era Mac wristwatch, 80s Memphis-style Swatches, early-90s
/// translucent "jelly" watches) without copying any of them outright.
/// Replaces the old `clockAnalog` boolean; see PLAN.md §8.1.
enum ClockFaceStyle: String, CaseIterable, Identifiable, Codable {
    case digital
    case lcd
    case classic
    case face2000
    case retroMac
    case memphis
    case jelly
    case colorTime

    var id: String { rawValue }

    /// Decodes a stored raw value, mapping the retired "swiss" name (that face
    /// is now Clock Face 2000) so an already-saved choice survives the rename.
    static func stored(_ rawValue: String) -> ClockFaceStyle? {
        rawValue == "swiss" ? .face2000 : ClockFaceStyle(rawValue: rawValue)
    }

    /// Whether this face renders an analog dial with hands (vs. digits).
    var isAnalog: Bool {
        switch self {
        case .digital, .lcd: return false
        default: return true
        }
    }

    /// Whether the face shows the time as text/digits, so the 12/24-hour
    /// preference applies to it.
    var usesTimeDigits: Bool { !isAnalog }

    var title: String {
        switch self {
        case .digital: return "Digital"
        case .lcd: return "LCD"
        case .classic: return "Classic"
        case .face2000: return "Clock Face 2000"
        case .retroMac: return "Retro Mac"
        case .memphis: return "Memphis"
        case .jelly: return "Jelly"
        case .colorTime: return "Color Time"
        }
    }

    /// A one-line description for the Settings pane.
    var caption: String {
        switch self {
        case .digital: return "Plain text time with optional date and weekday lines."
        case .lcd: return "A seven-segment readout in a classic resin sports-watch case."
        case .classic: return "Jetty's minimal glass dial with slim white hands."
        case .face2000: return "A clean station-style dial: rounded batons, orange ring second hand."
        case .retroMac: return "The mid-90s Mac wristwatch: blue metal bezel, green triangle, yellow squiggle."
        case .memphis: return "80s pop: confetti markers, pastel shapes, and outlined hands."
        case .jelly: return "Translucent 90s plastic with rainbow dot markers, tinted by your accent color."
        case .colorTime: return "Tells color time: an hour wedge sweeps a hidden color wheel, 70s style."
        }
    }
}
