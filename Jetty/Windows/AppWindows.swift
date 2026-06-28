import AppKit
import CoreGraphics
import ApplicationServices
import Darwin

/// One on-screen window of some application.
struct AppWindow: Identifiable {
    let id: CGWindowID
    var title: String
    let bounds: CGRect
    let pid: pid_t
}

/// Lists an application's on-screen windows via the public `CGWindowList` API. Window
/// ids and bounds need no permission; titles require Screen Recording (absent →
/// empty, which the UI handles). See PLAN.md §12.
enum WindowLister {
    static func windows(forPID pid: pid_t) -> [AppWindow] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else { return [] }
        var result: [AppWindow] = []
        for info in list {
            guard let owner = info[kCGWindowOwnerPID as String] as? NSNumber, owner.int32Value == pid,
                  let layer = info[kCGWindowLayer as String] as? NSNumber, layer.intValue == 0,  // normal windows only
                  let id = info[kCGWindowNumber as String] as? NSNumber,
                  let boundsDict = info[kCGWindowBounds as String] as? NSDictionary,
                  let rect = CGRect(dictionaryRepresentation: boundsDict as CFDictionary) else { continue }
            // Skip tiny utility/panel windows.
            guard rect.width >= 80, rect.height >= 80 else { continue }
            let title = (info[kCGWindowName as String] as? String) ?? ""
            result.append(AppWindow(id: CGWindowID(id.uint32Value), title: title, bounds: rect, pid: pid))
        }
        // Largest first — the main windows lead.
        return result.sorted { $0.bounds.width * $0.bounds.height > $1.bounds.width * $1.bounds.height }
    }
}

/// Captures a still image of a single window for the live-preview thumbnails. Requires
/// Screen Recording; returns `nil` (graceful) when it isn't granted.
enum WindowThumbnailer {
    static func image(for windowID: CGWindowID) -> CGImage? {
        CGWindowListCreateImage(.null, .optionIncludingWindow, windowID,
                                [.boundsIgnoreFraming, .nominalResolution])
    }
}

/// Raises / minimizes a specific window via the Accessibility API. No-ops gracefully
/// (raise falls back to merely activating the app) when Accessibility isn't trusted.
enum WindowActions {

    static func raise(_ window: AppWindow) {
        let running = NSRunningApplication(processIdentifier: window.pid)
        if let axWindow = axWindow(for: window) {
            AXUIElementPerformAction(axWindow, kAXRaiseAction as CFString)
        }
        if let running { AppLauncher.activate(running) }
    }

    static func minimize(_ window: AppWindow) {
        guard let axWindow = axWindow(for: window) else { return }
        AXUIElementSetAttributeValue(axWindow, kAXMinimizedAttribute as CFString, kCFBooleanTrue)
    }

    // MARK: AX window matching

    /// The AX window element whose CGWindowID matches, or nil (no AX trust / no match).
    private static func axWindow(for window: AppWindow) -> AXUIElement? {
        guard AXIsProcessTrusted(), let getWindow = Self.getWindowFn else { return nil }
        let app = AXUIElementCreateApplication(window.pid)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value) == .success,
              let axWindows = value as? [AXUIElement] else { return nil }
        for ax in axWindows {
            var wid = CGWindowID(0)
            if getWindow(ax, &wid) == .success, wid == window.id { return ax }
        }
        return nil
    }

    /// `_AXUIElementGetWindow` is a private but stable AppKit symbol that maps an AX
    /// window element to its `CGWindowID`. Resolved via `dlsym` so there's no link-time
    /// dependency — if it's ever unavailable, `axWindow(for:)` returns nil and raise
    /// degrades to activating the app.
    private typealias GetWindowFn = @convention(c) (AXUIElement, UnsafeMutablePointer<CGWindowID>) -> AXError
    private static let getWindowFn: GetWindowFn? = {
        // RTLD_DEFAULT searches all loaded images.
        guard let sym = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "_AXUIElementGetWindow") else { return nil }
        return unsafeBitCast(sym, to: GetWindowFn.self)
    }()
}
