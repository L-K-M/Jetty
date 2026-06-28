import Foundation
import AppKit

/// A shared countdown for the Pomodoro tile (ND-3). State lives in a singleton so it
/// survives dock rebuilds (the tile view is recreated whenever the model changes);
/// the tile tap toggles run/pause and a context action resets. Duration is read from
/// `Preferences` at (re)start.
final class PomodoroTimer: ObservableObject {

    static let shared = PomodoroTimer()

    @Published private(set) var remaining: TimeInterval
    @Published private(set) var isRunning = false

    private var duration: TimeInterval
    private var timer: Timer?
    private var endDate: Date?

    init(minutes: Double = Preferences.shared.pomodoroMinutes) {
        let seconds = max(minutes, 1) * 60
        duration = seconds
        remaining = seconds
    }

    /// Tap behavior: start when idle/paused, pause when running.
    func tap() { isRunning ? pause() : start() }

    func start() {
        if remaining <= 0 { reload() }
        isRunning = true
        endDate = Date().addingTimeInterval(remaining)
        timer?.invalidate()
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func pause() {
        updateRemaining()
        isRunning = false
        endDate = nil
        timer?.invalidate()
        timer = nil
    }

    func reset() {
        pause()
        reload()
    }

    private func reload() {
        duration = max(Preferences.shared.pomodoroMinutes, 1) * 60
        remaining = duration
        endDate = nil
    }

    private func tick() {
        updateRemaining()
        if remaining <= 0 {
            pause()
            NSSound(named: "Glass")?.play()
        }
    }

    private func updateRemaining(now: Date = Date()) {
        guard let endDate else { return }
        remaining = max(0, endDate.timeIntervalSince(now))
    }

    /// `mm:ss` for display.
    var displayString: String {
        let total = Int(remaining.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    /// Remaining fraction (1 → full, 0 → done) for the progress ring.
    var fraction: Double { duration > 0 ? max(0, min(remaining / duration, 1)) : 0 }
}
