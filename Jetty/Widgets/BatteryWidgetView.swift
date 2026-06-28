import SwiftUI

/// A battery info tile (ND-3): the charge percentage with a level glyph that gains a
/// charging glow when plugged in. Fed by the shared `LiveSystemStats` sampler so the
/// battery is read once per ~30s across all displays (ISSUE-5). On a Mac without a
/// battery it shows a power-plug glyph.
struct BatteryWidgetView: View {
    var height: CGFloat
    var tint: Color
    @ObservedObject private var stats = LiveSystemStats.shared

    var body: some View {
        content(stats.battery)
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
