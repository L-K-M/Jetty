import Foundation
import Darwin
import IOKit.ps

/// System data sources for the info-widget tiles (ND-3): battery state, CPU load,
/// and memory pressure. The *formatting* is pure and unit-tested; the *reads* use
/// public IOKit / Darwin APIs and degrade gracefully (a desktop Mac with no battery
/// returns `nil`).
enum SystemStats {

    // MARK: Battery

    struct Battery: Equatable {
        let percent: Int       // 0…100
        let isCharging: Bool
        let isPlugged: Bool
    }

    /// The current battery state, or `nil` on a Mac without a battery.
    static func battery() -> Battery? {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
        for source in sources {
            guard let desc = IOPSGetPowerSourceDescription(blob, source)?.takeUnretainedValue() as? [String: Any],
                  let current = desc[kIOPSCurrentCapacityKey as String] as? Int,
                  let max = desc[kIOPSMaxCapacityKey as String] as? Int, max > 0 else { continue }
            let percent = clampPercent(Int((Double(current) / Double(max) * 100).rounded()))
            let state = desc[kIOPSPowerSourceStateKey as String] as? String
            let isCharging = (desc[kIOPSIsChargingKey as String] as? Bool) ?? false
            let isPlugged = state == (kIOPSACPowerValue as String)
            return Battery(percent: percent, isCharging: isCharging, isPlugged: isPlugged)
        }
        return nil
    }

    static func clampPercent(_ p: Int) -> Int { Swift.min(Swift.max(p, 0), 100) }

    /// An SF Symbol matching a battery level + charging state.
    static func batterySymbol(percent: Int, isCharging: Bool) -> String {
        if isCharging { return "battery.100.bolt" }
        switch percent {
        case ..<13:  return "battery.0"
        case ..<38:  return "battery.25"
        case ..<63:  return "battery.50"
        case ..<88:  return "battery.75"
        default:     return "battery.100"
        }
    }

    // MARK: CPU / memory

    /// The 1-minute load average normalized by active core count → a 0…~1 figure
    /// (can exceed 1 when oversubscribed). Trivially robust (no mach interop).
    static func normalizedLoad() -> Double {
        var loads = [Double](repeating: 0, count: 3)
        _ = getloadavg(&loads, 3)
        let cores = Double(max(ProcessInfo.processInfo.activeProcessorCount, 1))
        return loads[0] / cores
    }

    /// The fraction of physical memory in use (active + wired + compressed), 0…1.
    /// Returns 0 if the mach query fails.
    static func memoryUsedFraction() -> Double {
        var stats = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride)
        let kr = withUnsafeMutablePointer(to: &stats) { pointer -> kern_return_t in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { reboundPtr in
                host_statistics64(mach_host_self(), HOST_VM_INFO64, reboundPtr, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return 0 }
        let pageSize = Double(vm_kernel_page_size)
        let used = (Double(stats.active_count) + Double(stats.wire_count)
                    + Double(stats.compressor_page_count)) * pageSize
        let total = Double(ProcessInfo.processInfo.physicalMemory)
        return total > 0 ? Swift.min(used / total, 1) : 0
    }

    // MARK: Network

    /// Cumulative bytes received/sent across all *active, non-loopback* interfaces, read
    /// from the link-layer counters via `getifaddrs`. Permission-free. These are running
    /// totals since boot — `LiveSystemStats` differences them into a per-second rate.
    /// Returns `(0, 0)` if the query fails.
    static func networkBytes() -> (received: UInt64, sent: UInt64) {
        var received: UInt64 = 0
        var sent: UInt64 = 0
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let first = head else { return (0, 0) }
        defer { freeifaddrs(head) }

        var node: UnsafeMutablePointer<ifaddrs>? = first
        while let current = node {
            defer { node = current.pointee.ifa_next }
            let flags = current.pointee.ifa_flags          // UInt32 bitmask of IFF_* flags
            guard (flags & UInt32(IFF_UP)) != 0, (flags & UInt32(IFF_LOOPBACK)) == 0,
                  let addr = current.pointee.ifa_addr,
                  addr.pointee.sa_family == UInt8(AF_LINK),
                  let raw = current.pointee.ifa_data else { continue }
            let data = raw.assumingMemoryBound(to: if_data.self).pointee
            received += UInt64(data.ifi_ibytes)
            sent += UInt64(data.ifi_obytes)
        }
        return (received, sent)
    }
}
