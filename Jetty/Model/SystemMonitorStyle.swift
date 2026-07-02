import Foundation

/// How the System Monitor tile presents CPU/RAM (and optionally network) — a
/// family of looks in the spirit of the clock's face styles.
/// - `bars`: two slim gauges (CPU + memory) — the original, compact look.
/// - `graph`: time-series sparklines on a dark glass plate.
/// - `scope`: a green-phosphor oscilloscope — glowing traces on a gridded CRT.
/// - `led`: a hi-fi LED meter — stacked green/amber/red segments per metric.
/// - `gauges`: two tiny analog dials with swinging needles and a redline.
enum SystemMonitorStyle: String, CaseIterable, Identifiable, Codable {
    case bars
    case graph
    case scope
    case led
    case gauges

    var id: String { rawValue }

    var title: String {
        switch self {
        case .bars: return "Bars"
        case .graph: return "Graph"
        case .scope: return "Scope"
        case .led: return "LEDs"
        case .gauges: return "Gauges"
        }
    }

    /// A one-line description for the Settings pane.
    var caption: String {
        switch self {
        case .bars: return "Two slim gauges for CPU load and memory usage."
        case .graph: return "CPU, memory, and optional network sparklines on a glass plate."
        case .scope: return "A green-phosphor oscilloscope: glowing traces on a gridded CRT."
        case .led: return "A hi-fi LED meter: stacked green/amber/red segments per metric."
        case .gauges: return "Two tiny analog dials with swinging needles and a redline."
        }
    }

    /// Whether the style plots a network-throughput series (time-series looks only).
    var supportsNetwork: Bool {
        switch self {
        case .graph, .scope: return true
        default: return false
        }
    }
}
