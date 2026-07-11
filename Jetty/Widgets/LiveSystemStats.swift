import Foundation
import Combine
import Darwin

/// One throttled, recent-history sample of the live system metrics.
struct SystemSample: Equatable {
    var load: Double      // CPU: normalized 1-min load average (0…~1+, can exceed 1)
    var memory: Double    // memory used fraction (0…1)
    var netDown: Double   // bytes/second received
    var netUp: Double     // bytes/second sent
}

/// One shared, throttled sampler for the live system widgets. Each `TimelineView`
/// tile used to poll CPU/memory/battery on its own, so N displays meant N
/// independent samples every tick (ISSUE-5). This reads each source **once** per
/// tick regardless of how many panels show the widget.
///
/// The timer is driven by the `DockController` (`setRunning`) from the authoritative
/// tile/panel state rather than SwiftUI `onAppear`/`onDisappear` — an ordered-out
/// panel doesn't reliably deliver `onDisappear`, which would otherwise leak the timer.
///
/// CPU/memory/network are sampled on the base interval; battery (which moves slowly
/// and is pricier) only every `batteryEvery` ticks. A bounded ring buffer of recent
/// samples (`history`) backs the System Monitor's graph style.
final class LiveSystemStats: ObservableObject {
    static let shared = LiveSystemStats()

    @Published private(set) var load: Double = 0
    @Published private(set) var memory: Double = 0
    @Published private(set) var battery: SystemStats.Battery?
    /// Recent samples, oldest → newest, for the graph style. Bounded to `historyCapacity`.
    @Published private(set) var history: [SystemSample] = []

    private let interval: TimeInterval = 2
    private let batteryEvery = 15          // 2s × 15 = ~30s, matching the old battery cadence
    /// 60 samples × 2s ≈ a 2-minute window in the graph.
    let historyCapacity = 60
    private var timer: Timer?
    private var timerGeneration = 0
    private var tick = 0
    private var resetHistoryOnNextSample = false
    /// Previous cumulative network counters and monotonic read time, used to calculate
    /// a real per-second rate even when the timer is coalesced or delayed.
    private var lastNetwork: (counters: (received: UInt64, sent: UInt64), uptime: TimeInterval)?

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
        timerGeneration += 1
        let generation = timerGeneration
        tick = 0
        // Drop the stale network baseline so the first post-(re)start delta is 0 rather
        // than a huge spike covering however long the sampler was off.
        lastNetwork = nil
        resetHistoryOnNextSample = true
        // First reading on the next runloop turn — never synchronously inside a caller
        // that might be mid-view-update (avoids "Publishing changes from within view
        // updates").
        DispatchQueue.main.async { [weak self] in
            guard let self, self.timer != nil,
                  self.timerGeneration == generation else { return }
            self.sample(includeBattery: true)
        }
        let t = Timer(timeInterval: interval, repeats: true) { [weak self] _ in self?.onTick() }
        t.tolerance = interval * 0.1
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func stopTimer() {
        timerGeneration += 1
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

        let counters = SystemStats.networkBytes()
        let uptime = Self.continuousTime()
        let elapsed = lastNetwork.map { uptime - $0.uptime }
        let longGap = elapsed.map { Self.isLongSamplingGap(elapsed: $0, expected: interval) } ?? false
        let rate = Self.throughput(current: counters,
                                   previous: longGap ? nil : lastNetwork?.counters,
                                   interval: elapsed ?? 0)
        lastNetwork = (counters, uptime)
        let previousHistory = (longGap || resetHistoryOnNextSample) ? [] : history
        resetHistoryOnNextSample = false
        history = Self.appending(SystemSample(load: load, memory: memory, netDown: rate.down, netUp: rate.up),
                                 to: previousHistory, cap: historyCapacity)

        if includeBattery { battery = SystemStats.battery() }
    }

    // MARK: Pure helpers (unit-tested)

    /// Appends `sample`, trimming the oldest entries so the buffer never exceeds `cap`.
    static func appending(_ sample: SystemSample, to history: [SystemSample], cap: Int) -> [SystemSample] {
        guard cap > 0 else { return [] }
        var next = history
        next.append(sample)
        if next.count > cap { next.removeFirst(next.count - cap) }
        return next
    }

    /// Per-second throughput from two cumulative counter reads. Returns `(0, 0)` when
    /// there's no previous read, a non-positive interval, or the counters went backwards
    /// (a 32-bit wrap or interface reset) — never a negative or garbage rate.
    static func throughput(current: (received: UInt64, sent: UInt64),
                           previous: (received: UInt64, sent: UInt64)?,
                           interval: TimeInterval) -> (down: Double, up: Double) {
        guard let previous, interval > 0 else { return (0, 0) }
        let down = current.received >= previous.received ? Double(current.received - previous.received) / interval : 0
        let up = current.sent >= previous.sent ? Double(current.sent - previous.sent) / interval : 0
        return (down, up)
    }

    /// A long suspension should start a new graph segment rather than compressing an
    /// arbitrary sleep/wake interval into one sample. Timer jitter below three normal
    /// intervals still uses its real elapsed duration.
    static func isLongSamplingGap(elapsed: TimeInterval, expected: TimeInterval) -> Bool {
        guard elapsed.isFinite, elapsed >= 0, expected > 0 else { return true }
        return elapsed >= expected * 3
    }

    /// Monotonic time that includes system sleep, unlike uptime clocks that can pause
    /// while asleep. This keeps counter deltas and elapsed time on the same real-world
    /// interval and lets the long-gap gate identify wake samples.
    private static func continuousTime() -> TimeInterval {
        var timebase = mach_timebase_info_data_t()
        mach_timebase_info(&timebase)
        let nanos = Double(mach_continuous_time())
            * Double(timebase.numer) / Double(timebase.denom)
        return nanos / 1_000_000_000
    }
}
