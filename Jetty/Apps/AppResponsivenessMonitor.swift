import ApplicationServices
import Foundation

/// Best-effort app responsiveness checks using Accessibility only when the user has
/// already granted it. The monitor never prompts and never guesses from process state.
final class AppResponsivenessMonitor {

    enum ProbeOutcome {
        case responsive
        case timedOut
        case unavailable
    }

    static let failuresRequired = 3

    private struct Target: Hashable {
        let pid: pid_t
        let launchDate: TimeInterval?
    }

    private final class ProbeResults {
        private let lock = NSLock()
        private var values: [Target: ProbeOutcome] = [:]

        func set(_ outcome: ProbeOutcome, for target: Target) {
            lock.lock()
            values[target] = outcome
            lock.unlock()
        }

        func outcome(for target: Target) -> ProbeOutcome {
            lock.lock()
            defer { lock.unlock() }
            return values[target] ?? .unavailable
        }
    }

    var onChange: ((Set<pid_t>) -> Void)?

    private let stateQueue = DispatchQueue(label: "com.lkm.jetty.app-responsiveness", qos: .utility)
    private let probeQueue = DispatchQueue(label: "com.lkm.jetty.app-responsiveness.probes",
                                           qos: .utility, attributes: .concurrent)
    private let isTrusted: () -> Bool
    private let probe: (pid_t) -> ProbeOutcome
    private let now: () -> TimeInterval

    private var timer: DispatchSourceTimer?
    private var targets = Set<Target>()
    private var firstSeen: [Target: TimeInterval] = [:]
    private var failures: [Target: Int] = [:]
    private var unresponsive = Set<pid_t>()
    private var lastPublished = Set<pid_t>()
    private var generation = 0
    private var nextRoundID = 0
    private var activeRoundID: Int?

    init(isTrusted: @escaping () -> Bool = { AccessibilityAuthorizer.isTrusted },
         probe: @escaping (pid_t) -> ProbeOutcome = AppResponsivenessMonitor.axProbe,
         now: @escaping () -> TimeInterval = { Date().timeIntervalSinceReferenceDate }) {
        self.isTrusted = isTrusted
        self.probe = probe
        self.now = now
    }

    func start() {
        stateQueue.async { [weak self] in
            guard let self, self.timer == nil else { return }
            let timer = DispatchSource.makeTimerSource(queue: self.stateQueue)
            timer.schedule(deadline: .now() + 2, repeating: 5, leeway: .seconds(1))
            timer.setEventHandler { [weak self] in self?.runRound() }
            self.timer = timer
            timer.resume()
        }
    }

    func stop() {
        stateQueue.async { [weak self] in
            guard let self else { return }
            self.generation &+= 1
            self.timer?.cancel()
            self.timer = nil
            self.targets.removeAll()
            self.firstSeen.removeAll()
            self.failures.removeAll()
            self.unresponsive.removeAll()
            self.publishIfChanged()
        }
    }

    func resetAfterWake() {
        stateQueue.async { [weak self] in
            guard let self else { return }
            self.generation &+= 1
            self.failures.removeAll()
            self.unresponsive.removeAll()
            let timestamp = self.now()
            self.firstSeen = Dictionary(uniqueKeysWithValues: self.targets.map { ($0, timestamp) })
            self.publishIfChanged()
        }
    }

    func setApplications(_ applications: [RunningAppInfo]) {
        let next = Set(applications.map {
            Target(pid: $0.pid, launchDate: $0.launchDate?.timeIntervalSinceReferenceDate)
        })
        stateQueue.async { [weak self] in
            guard let self, next != self.targets else { return }
            self.generation &+= 1
            let retainedPIDs = Set(self.targets.intersection(next).map(\.pid))
            self.targets = next
            let timestamp = self.now()
            for target in next where self.firstSeen[target] == nil {
                self.firstSeen[target] = min(timestamp, target.launchDate ?? timestamp)
            }
            self.firstSeen = self.firstSeen.filter { next.contains($0.key) }
            self.failures = self.failures.filter { next.contains($0.key) }
            self.unresponsive.formIntersection(retainedPIDs)
            self.publishIfChanged()
        }
    }

    static func nextFailureCount(current: Int, outcome: ProbeOutcome) -> Int {
        switch outcome {
        case .responsive, .unavailable: return 0
        case .timedOut: return min(failuresRequired, current + 1)
        }
    }

    static func axProbe(pid: pid_t) -> ProbeOutcome {
        let application = AXUIElementCreateApplication(pid)
        _ = AXUIElementSetMessagingTimeout(application, 0.5)
        var value: CFTypeRef?
        switch AXUIElementCopyAttributeValue(application, kAXRoleAttribute as CFString, &value) {
        case .success: return .responsive
        case .cannotComplete: return .timedOut
        default: return .unavailable
        }
    }

    private func runRound() {
        guard activeRoundID == nil else { return }
        guard isTrusted() else {
            failures.removeAll()
            unresponsive.removeAll()
            publishIfChanged()
            return
        }

        let timestamp = now()
        let eligible = targets.filter { timestamp - (firstSeen[$0] ?? timestamp) >= 15 }
        guard !eligible.isEmpty else { return }

        nextRoundID &+= 1
        let roundID = nextRoundID
        activeRoundID = roundID
        let roundGeneration = generation
        let group = DispatchGroup()
        let gate = DispatchSemaphore(value: 4)
        let results = ProbeResults()

        for target in eligible {
            group.enter()
            probeQueue.async { [weak self] in
                gate.wait()
                let outcome = self?.probe(target.pid) ?? .unavailable
                gate.signal()
                results.set(outcome, for: target)
                group.leave()
            }
        }

        group.notify(queue: stateQueue) { [weak self] in
            guard let self else { return }
            guard self.activeRoundID == roundID else { return }
            self.activeRoundID = nil
            guard self.generation == roundGeneration else { return }
            for target in eligible where self.targets.contains(target) {
                let count = Self.nextFailureCount(current: self.failures[target] ?? 0,
                                                  outcome: results.outcome(for: target))
                if count == 0 { self.failures[target] = nil } else { self.failures[target] = count }
                if count >= Self.failuresRequired {
                    self.unresponsive.insert(target.pid)
                } else {
                    self.unresponsive.remove(target.pid)
                }
            }
            self.publishIfChanged()
        }
    }

    private func publishIfChanged() {
        guard unresponsive != lastPublished else { return }
        lastPublished = unresponsive
        let value = unresponsive
        DispatchQueue.main.async { [weak self] in self?.onChange?(value) }
    }
}
