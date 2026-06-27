import SwiftUI

/// A battery info tile (ND-3): the charge percentage with a level glyph that gains a
/// charging glow when plugged in. Polls every 30s via `TimelineView` (no manual
/// timer). On a Mac without a battery it shows a power-plug glyph.
struct BatteryWidgetView: View {
    var height: CGFloat
    var tint: Color

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { _ in
            content(SystemStats.battery())
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .help("Battery")
    }

    @ViewBuilder
    private func content(_ battery: SystemStats.Battery?) -> some View {
        if let battery {
            VStack(spacing: 1) {
                Image(systemName: SystemStats.batterySymbol(percent: battery.percent, isCharging: battery.isCharging))
                    .font(.system(size: max(13, height * 0.34)))
                    .foregroundStyle(battery.isCharging ? Color.green : .primary)
                    .shadow(color: battery.isCharging ? Color.green.opacity(0.7) : .clear,
                            radius: battery.isCharging ? 4 : 0)
                Text("\(battery.percent)%")
                    .font(.system(size: max(9, height * 0.2), weight: .semibold, design: .rounded))
                    .monospacedDigit()
            }
        } else {
            Image(systemName: "powerplug.fill")
                .font(.system(size: max(13, height * 0.34)))
                .foregroundStyle(.secondary)
        }
    }
}
