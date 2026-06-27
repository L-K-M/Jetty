import AppKit

/// A small fixed-capacity, time-bounded cache of icons keyed by a string (a dock
/// tile id). LRU eviction keeps memory bounded; a TTL lets an app's icon refresh
/// after it changes (app update / theme) instead of going stale forever — the two
/// problems BUG-8 flagged about the old unbounded dictionary. The current time is
/// injected so eviction/expiry is deterministic under test.
struct LRUImageCacheByKey {

    let capacity: Int
    let maxAge: TimeInterval

    private struct Entry { let image: NSImage; let timestamp: TimeInterval }
    private var order: [String] = []          // least- to most-recently used
    private var store: [String: Entry] = [:]

    init(capacity: Int, maxAge: TimeInterval) {
        self.capacity = max(1, capacity)
        self.maxAge = maxAge
    }

    var count: Int { store.count }

    mutating func value(for key: String, now: TimeInterval) -> NSImage? {
        guard let entry = store[key] else { return nil }
        guard now - entry.timestamp <= maxAge else { remove(key); return nil }
        promote(key)
        return entry.image
    }

    mutating func insert(_ image: NSImage, for key: String, now: TimeInterval) {
        store[key] = Entry(image: image, timestamp: now)
        promote(key)
        while order.count > capacity, let oldest = order.first { remove(oldest) }
    }

    mutating func remove(_ key: String) {
        store[key] = nil
        order.removeAll { $0 == key }
    }

    private mutating func promote(_ key: String) {
        order.removeAll { $0 == key }
        order.append(key)
    }
}
