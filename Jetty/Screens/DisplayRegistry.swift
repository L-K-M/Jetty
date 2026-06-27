import AppKit

/// Maps each connected display to a **stable UUID** and back to the current
/// `NSScreen`, rebuilding on any screen-parameters change. `CGDirectDisplayID`s are
/// reassigned across reboots/reconnections, so a display's UUID
/// (`CGDisplayCreateUUIDFromDisplayID`) is the durable key Jetty anchors docks to.
/// See PLAN.md §5.
final class DisplayRegistry {

    /// Invoked (on the main thread) whenever the set/arrangement of screens changes.
    var onChange: (() -> Void)?

    private(set) var screensByUUID: [String: NSScreen] = [:]

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
        var map: [String: NSScreen] = [:]
        for screen in NSScreen.screens {
            if let uuid = Self.uuid(for: screen) { map[uuid] = screen }
        }
        screensByUUID = map
    }

    func screen(forUUID uuid: String) -> NSScreen? { screensByUUID[uuid] }

    func uuid(for screen: NSScreen) -> String? { Self.uuid(for: screen) }

    /// All currently-connected display UUIDs.
    func allUUIDs() -> [String] { Array(screensByUUID.keys) }

    /// The UUID of the main display (the one with the menu bar / key window), if known.
    func mainScreenUUID() -> String? {
        guard let main = NSScreen.main else { return screensByUUID.keys.first }
        return Self.uuid(for: main)
    }

    /// Stable UUID string for a screen, via its `CGDirectDisplayID`.
    static func uuid(for screen: NSScreen) -> String? {
        guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return nil
        }
        let displayID = CGDirectDisplayID(number.uint32Value)
        guard let cfUUID = CGDisplayCreateUUIDFromDisplayID(displayID)?.takeRetainedValue() else { return nil }
        return CFUUIDCreateString(nil, cfUUID) as String
    }
}
