import SwiftUI

/// The Pomodoro tile (ND-3): a progress ring around the remaining `mm:ss`, driven by
/// the shared `PomodoroTimer`. Tapping the tile (handled by the dock) starts/pauses;
/// the ring drains as time elapses and the digits dim while paused.
struct PomodoroWidgetView: View {
    @ObservedObject private var timer = PomodoroTimer.shared
    var height: CGFloat
    var tint: Color

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.primary.opacity(0.15), lineWidth: max(2, height * 0.06))
            Circle()
                // A completed session keeps a full ring + "Done" until the next start
                // instead of a dimmed 0:00 that reads as stalled.
                .trim(from: 0, to: timer.isCompleted ? 1 : timer.fraction)
                .stroke(tint, style: StrokeStyle(lineWidth: max(2, height * 0.06), lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 0.3), value: timer.fraction)
            Text(timer.isCompleted ? "Done" : timer.displayString)
                .font(.system(size: max(9, height * 0.22), weight: .semibold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.5)   // long sessions (h:mm:ss) must not overflow (M33)
                .opacity(timer.isRunning || timer.isCompleted ? 1 : 0.6)
        }
        .padding(height * 0.12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .help(timer.isCompleted ? "Pomodoro finished — tap to start again"
                                : (timer.isRunning ? "Pomodoro running — tap to pause" : "Pomodoro — tap to start"))
    }
}
