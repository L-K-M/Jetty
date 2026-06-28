import Foundation
import Combine

/// One shared, throttled sampler for the live system widgets. Each `TimelineView`
/// tile used to poll CPU/memory/battery on its own, so N displays meant N
/// independent samples every tick (ISSUE-5). This reads each source **once** per
/// tick regardless of how many panels show the widget.
///
/// The timer is driven by the `DockController` (`setRunning`) from the authoritative
/// tile/panel state rather than SwiftUI `onAppear`/`onDisappear` — an ordered-out
/// panel doesn't reliably deliver `onDisappear`, which would otherwise leak the timer.
///
/// CPU/memory are sampled on the base interval; battery (which moves slowly and is
/// pricier) only every `batteryEvery` ticks.
final class LiveSystemStats: ObservableObject {
    static let shared = LiveSystemStats()

    @Published private(set) var load: Double = 0
    @Published private(set) var memory: Double = 0
    @Published private(set) var battery: SystemStats.Battery?

    private let interval: TimeInterval = 2
    private let batteryEvery = 15          // 2s × 15 = ~30s, matching the old battery cadence
    private var timer: Timer?
    private var tick = 0

    private init() {}

    /// Turn the shared sampler on/off. Idempotent: enabling while already running keeps
    /// the current cadence (no resample); disabling stops the timer.
    func setRunning(_ running: Bool) {
        if running {
            if timer == nil { startTimer() }
        } else {
            stopTimer()
        }
    }

    private func startTimer() {
        tick = 0
        // First reading on the next runloop turn — never synchronously inside a caller
        // that might be mid-view-update (avoids "Publishing changes from within view
        // updates").
        DispatchQueue.main.async { [weak self] in
            guard let self, self.timer != nil else { return }
            self.sample(includeBattery: true)
        }
        let t = Timer(timeInterval: interval, repeats: true) { [weak self] _ in self?.onTick() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func onTick() {
        tick += 1
        sample(includeBattery: tick % batteryEvery == 0)
    }

    private func sample(includeBattery: Bool) {
        load = SystemStats.normalizedLoad()
        memory = SystemStats.memoryUsedFraction()
        if includeBattery { battery = SystemStats.battery() }
    }
}
