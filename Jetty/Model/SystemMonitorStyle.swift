import Foundation

/// How the System Monitor tile presents itself (ND-3 follow-up).
/// - `bars`: two slim gauges (CPU + memory) — the original, compact look.
/// - `graph`: a time-series sparkline of CPU and memory (and optionally network),
///   so you can read the trend at a glance, not just the instant value.
enum SystemMonitorStyle: String, CaseIterable, Identifiable, Codable {
    case bars
    case graph

    var id: String { rawValue }

    var title: String {
        switch self {
        case .bars: return "Bars"
        case .graph: return "Graph"
        }
    }
}
