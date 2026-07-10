import AppKit
import Combine

/// Maps each connected display to a **stable UUID** and back to the current
/// `NSScreen`, rebuilding on any screen-parameters change. `CGDirectDisplayID`s are
/// reassigned across reboots/reconnections, so a display's UUID
/// (`CGDisplayCreateUUIDFromDisplayID`) is the durable key Jetty anchors docks to.
/// See PLAN.md §5.
final class DisplayRegistry: ObservableObject {

    struct Entry: Identifiable {
        let id: String
        let name: String
        let screen: NSScreen
    }

    /// Invoked (on the main thread) whenever the set/arrangement of screens changes.
    var onChange: (() -> Void)?

    private(set) var screensByUUID: [String: NSScreen] = [:]
    @Published private(set) var entries: [Entry] = []
    /// Retains in-session assignments for disconnected screens so reconnect order does
    /// not swap collision suffixes. The base UUID is revalidated before reuse.
    private var keyByDisplayID: [CGDirectDisplayID: String] = [:]
    private var keyByScreenObject: [ObjectIdentifier: String] = [:]
    private var reservedHistoricalKeys = Set<String>()

    init() {
        rebuild()
        NotificationCenter.default.addObserver(
            self, selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    @objc private func screensChanged() {
        rebuild()
        onChange?()
    }

    func rebuild() {
        let screens = NSScreen.screens
        let previousKeys = keyByDisplayID
        let previousObjectKeys = keyByScreenObject
        // Historical display-ID assignments remain reserved for this app session, even
        // while disconnected, so a newcomer cannot steal a suffix before the original
        // display reconnects.
        let reservedKeys = reservedHistoricalKeys
            .union(previousKeys.values)
            .union(previousObjectKeys.values)
        var map: [String: NSScreen] = [:]
        var reverse = previousKeys
        var objectReverse: [ObjectIdentifier: String] = [:]
        var rebuiltEntries: [Entry] = []
        for screen in screens {
            // A physical display must NEVER be dropped from the registry — otherwise it
            // gets no dock panel at all (BUG: a side-by-side display showed no dock). Some
            // displays don't report a hardware UUID (`CGDisplayCreateUUIDFromDisplayID`
            // returns nil for certain virtual/adapter/small displays), and in rare cases
            // two report the same one. Use a never-nil key and disambiguate collisions so
            // every connected screen keeps its own entry.
            let baseKey = Self.key(for: screen)
            let displayID = Self.displayID(for: screen)
            let objectID = ObjectIdentifier(screen)
            let previousKey = (displayID.flatMap { previousKeys[$0] }
                ?? previousObjectKeys[objectID])
                .flatMap { $0 == baseKey || $0.hasPrefix("\(baseKey)#") ? $0 : nil }
            var uniqueKey = previousKey ?? baseKey
            var n = 2
            while map[uniqueKey] != nil
                    || (reservedKeys.contains(uniqueKey) && uniqueKey != previousKey) {
                uniqueKey = "\(baseKey)#\(n)"
                n += 1
            }
            map[uniqueKey] = screen
            if let displayID { reverse[displayID] = uniqueKey }
            objectReverse[objectID] = uniqueKey
            rebuiltEntries.append(Entry(id: uniqueKey, name: screen.localizedName, screen: screen))
        }
        screensByUUID = map
        keyByDisplayID = reverse
        keyByScreenObject = objectReverse
        reservedHistoricalKeys.formUnion(map.keys)
        entries = rebuiltEntries
    }

    func screen(forUUID uuid: String) -> NSScreen? { screensByUUID[uuid] }

    /// The stable key Jetty anchors a dock to for `screen` — its hardware UUID when the
    /// system provides one, else a per-screen fallback so a screen is never dropped.
    func key(for screen: NSScreen) -> String {
        Self.displayID(for: screen).flatMap { keyByDisplayID[$0] }
            ?? keyByScreenObject[ObjectIdentifier(screen)]
            ?? Self.key(for: screen)
    }

    /// All currently-connected display keys.
    func allUUIDs() -> [String] { entries.map(\.id) }

    /// The hardware UUID for a display, or nil if the system doesn't report one.
    static func uuid(for screen: NSScreen) -> String? {
        guard let displayID = displayID(for: screen) else { return nil }
        guard let cfUUID = CGDisplayCreateUUIDFromDisplayID(displayID)?.takeRetainedValue() else { return nil }
        return CFUUIDCreateString(nil, cfUUID) as String
    }

    /// A stable, non-nil key for a display: its hardware UUID, else a fallback derived
    /// from its `CGDirectDisplayID` (unique within a session), so a screen without a
    /// reported UUID still gets its own dock and its own settings entry.
    static func key(for screen: NSScreen) -> String {
        if let uuid = uuid(for: screen) { return uuid }
        return "screen:\(displayID(for: screen) ?? 0)"
    }

    private static func displayID(for screen: NSScreen) -> CGDirectDisplayID? {
        guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return nil
        }
        return CGDirectDisplayID(number.uint32Value)
    }
}
