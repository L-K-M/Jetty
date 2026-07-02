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
            let low = SystemStats.isLowBattery(percent: battery.percent, isPlugged: battery.isPlugged)
            VStack(spacing: 1) {
                Image(systemName: SystemStats.batterySymbol(percent: battery.percent))
                    .font(.system(size: max(13, height * 0.34)))
                    .foregroundStyle(low ? Color.red : (battery.isCharging ? Color.green : .primary))
                    .overlay(alignment: .center) { chargeBadge(battery) }
                    .shadow(color: battery.isCharging ? Color.green.opacity(0.7) : .clear,
                            radius: battery.isCharging ? 4 : 0)
                Text("\(battery.percent)%")
                    .font(.system(size: max(9, height * 0.2), weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(low ? Color.red : .primary)
            }
        } else {
            Image(systemName: "powerplug.fill")
                .font(.system(size: max(13, height * 0.34)))
                .foregroundStyle(.secondary)
        }
    }

    /// A small glyph inside the battery outline: a bolt while charging, or a plug when
    /// plugged in but not charging (held at 80% by Optimized Charging, or full on AC)
    /// so that state reads differently from running on battery (F-L6).
    @ViewBuilder
    private func chargeBadge(_ battery: SystemStats.Battery) -> some View {
        if battery.isCharging {
            Image(systemName: "bolt.fill")
                .font(.system(size: max(7, height * 0.16), weight: .bold))
                .foregroundStyle(.white)
        } else if battery.isPlugged {
            Image(systemName: "powerplug.fill")
                .font(.system(size: max(6, height * 0.14)))
                .foregroundStyle(.secondary)
        }
    }
}
