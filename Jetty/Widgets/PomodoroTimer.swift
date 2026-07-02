import Foundation
import AppKit
import Combine

/// A shared countdown for the Pomodoro tile (ND-3). State lives in a singleton so it
/// survives dock rebuilds (the tile view is recreated whenever the model changes);
/// the tile tap toggles run/pause and a context action resets. Duration is read from
/// `Preferences` at (re)start.
///
/// Robustness: the countdown **freezes across sleep** (re-anchoring the deadline on
/// wake, so closing the lid mid-session no longer completes it instantly — H12), and
/// its state is **persisted** so an updater relaunch resumes rather than resets.
final class PomodoroTimer: ObservableObject {

    static let shared = PomodoroTimer()

    @Published private(set) var remaining: TimeInterval
    @Published private(set) var isRunning = false

    private var duration: TimeInterval
    private var timer: Timer?
    private var endDate: Date?
    /// Remaining captured at sleep so wake can re-anchor `endDate` instead of letting
    /// the first post-wake tick see a huge elapsed and "complete" instantly (H12).
    private var remainingAtSleep: TimeInterval?
    private var cancellables = Set<AnyCancellable>()

    private let defaults: UserDefaults
    private enum Key {
        static let endDate = "pomodoro.endDate"
        static let remaining = "pomodoro.remaining"
        static let isRunning = "pomodoro.isRunning"
        static let duration = "pomodoro.duration"
    }

    init(defaults: UserDefaults = .standard, minutes: Double = Preferences.shared.pomodoroMinutes) {
        self.defaults = defaults
        let seconds = max(minutes, 1) * 60
        duration = seconds
        remaining = seconds
        restore()
        observeSleepWake()
        observeDurationChanges()
    }

    /// Tap behavior: start when idle/paused, pause when running.
    func tap() { isRunning ? pause() : start() }

    func start() {
        // Pick up a changed session length when starting fresh — idle at the full
        // duration, or after a completed session — but preserve a paused mid-session
        // (its `remaining` is below `duration`), so the new length isn't ignored (F-M7).
        if remaining <= 0 || (!isRunning && endDate == nil && remaining == duration) { reload() }
        isRunning = true
        endDate = Date().addingTimeInterval(remaining)
        startTicking()
        save()
    }

    func pause() {
        updateRemaining()
        isRunning = false
        endDate = nil
        timer?.invalidate()
        timer = nil
        save()
    }

    func reset() {
        pause()
        reload()
        save()
    }

    private func reload() {
        duration = max(Preferences.shared.pomodoroMinutes, 1) * 60
        remaining = duration
        endDate = nil
    }

    private func startTicking() {
        timer?.invalidate()
        let t = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
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

    // MARK: Sleep / wake (H12)

    private func observeSleepWake() {
        let nc = NSWorkspace.shared.notificationCenter
        nc.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            self?.handleWillSleep()
        }
        nc.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.handleDidWake()
        }
    }

    private func handleWillSleep() {
        guard isRunning else { return }
        updateRemaining()                 // freeze the current remaining
        remainingAtSleep = remaining
        timer?.invalidate(); timer = nil  // no stale tick can fire on wake
        save()
    }

    private func handleDidWake() {
        guard isRunning, let frozen = remainingAtSleep else { return }
        remainingAtSleep = nil
        remaining = frozen
        endDate = Date().addingTimeInterval(frozen)   // resume from where we froze
        startTicking()
        save()
    }

    // MARK: Live session-length changes (F-M7)

    private func observeDurationChanges() {
        Preferences.shared.$pomodoroMinutes
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                // Only refresh the *idle, untouched* tile so a running/paused session
                // isn't disturbed by editing the preference.
                guard let self, !self.isRunning, self.endDate == nil,
                      self.remaining == self.duration else { return }
                self.reload()
            }
            .store(in: &cancellables)
    }

    // MARK: Persistence

    private func save() {
        defaults.set(duration, forKey: Key.duration)
        defaults.set(remaining, forKey: Key.remaining)
        defaults.set(isRunning, forKey: Key.isRunning)
        if let endDate { defaults.set(endDate.timeIntervalSinceReferenceDate, forKey: Key.endDate) }
        else { defaults.removeObject(forKey: Key.endDate) }
    }

    private func restore() {
        guard defaults.object(forKey: Key.duration) != nil else { return }
        let savedDuration = defaults.double(forKey: Key.duration)
        if savedDuration > 0 { duration = savedDuration }

        if defaults.bool(forKey: Key.isRunning), defaults.object(forKey: Key.endDate) != nil {
            let end = Date(timeIntervalSinceReferenceDate: defaults.double(forKey: Key.endDate))
            let left = max(0, end.timeIntervalSinceReferenceDate - Date().timeIntervalSinceReferenceDate)
            remaining = left
            if left > 0 {
                endDate = end
                isRunning = true
                startTicking()
            }
            // If it elapsed while we were gone, stay stopped at 0 — don't replay the sound.
        } else if defaults.object(forKey: Key.remaining) != nil {
            remaining = defaults.double(forKey: Key.remaining)   // preserve a paused/idle value
        }
    }

    // MARK: Display

    /// The remaining time, `m:ss` under an hour and `h:mm:ss` past it, so long sessions
    /// (up to the 180-minute max) read clearly instead of an ambiguous `180:00` (M33).
    /// Pure — unit-tested.
    static func format(remaining: TimeInterval) -> String {
        let total = max(0, Int(remaining.rounded()))
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }

    var displayString: String { Self.format(remaining: remaining) }

    /// Remaining fraction (1 → full, 0 → done) for the progress ring.
    var fraction: Double { duration > 0 ? max(0, min(remaining / duration, 1)) : 0 }
}
