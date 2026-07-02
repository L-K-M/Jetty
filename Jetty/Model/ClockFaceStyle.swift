import Foundation

/// The look of the date/time dock tile — the plain text style, a retro
/// seven-segment LCD, or one of the analog dials modeled on iconic watch faces
/// (the Swiss railway station clock, the mid-90s rainbow-era Mac wristwatch,
/// 80s Memphis-style Swatches, early-90s translucent "jelly" watches).
/// Replaces the old `clockAnalog` boolean; see PLAN.md §8.1.
enum ClockFaceStyle: String, CaseIterable, Identifiable, Codable {
    case digital
    case lcd
    case classic
    case swiss
    case retroMac
    case memphis
    case jelly

    var id: String { rawValue }

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
        case .swiss: return "Swiss Railway"
        case .retroMac: return "Retro Mac"
        case .memphis: return "Memphis"
        case .jelly: return "Jelly"
        }
    }

    /// A one-line description for the Settings pane.
    var caption: String {
        switch self {
        case .digital: return "Plain text time with optional date and weekday lines."
        case .lcd: return "A seven-segment digital readout, like an 80s wrist calculator watch."
        case .classic: return "Jetty's minimal glass dial with slim white hands."
        case .swiss: return "The station clock: bold batons and a red lollipop second hand."
        case .retroMac: return "The mid-90s Mac wristwatch: green triangle, red baton, yellow squiggle."
        case .memphis: return "80s pop: a cream dial with confetti shapes for markers."
        case .jelly: return "Early-90s translucent plastic, tinted with your accent color."
        }
    }
}
