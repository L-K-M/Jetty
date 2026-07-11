import AppKit
import CoreGraphics
import ApplicationServices
import ScreenCaptureKit
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
        // CGWindowList only yields kCGWindowName with Screen Recording. Fill missing
        // titles from Accessibility when that's granted (no Screen Recording needed) so
        // the names view is useful without the capture permission.
        let axTitles = WindowActions.titles(forPID: pid)
        let merged: [AppWindow] = result.map { window in
            guard window.title.isEmpty, let title = axTitles[window.id] else { return window }
            var copy = window
            copy.title = title
            return copy
        }
        // Largest first — the main windows lead.
        return merged.sorted { $0.bounds.width * $0.bounds.height > $1.bounds.width * $1.bounds.height }
    }
}

/// Captures live thumbnails for the preview popover via **ScreenCaptureKit** (the
/// modern replacement for the deprecated `CGWindowListCreateImage`). Requires Screen
/// Recording; returns an empty map (graceful → the UI shows a window glyph) when it
/// isn't granted, or on macOS 13 where `SCScreenshotManager` isn't available.
enum WindowThumbnailer {
    static func images(for windows: [AppWindow]) async -> [CGWindowID: CGImage] {
        guard !windows.isEmpty else { return [:] }
        if #available(macOS 14, *) { return await sckImages(for: windows) }
        return [:]
    }

    /// Fetches the shareable-content list **once**, then captures each requested window
    /// from it — far cheaper than querying the window server per window.
    @available(macOS 14, *)
    private static func sckImages(for windows: [AppWindow]) async -> [CGWindowID: CGImage] {
        guard !Task.isCancelled else { return [:] }
        guard let content = try? await SCShareableContent.current else { return [:] }
        guard !Task.isCancelled else { return [:] }
        let byID = Dictionary(content.windows.map { ($0.windowID, $0) }, uniquingKeysWith: { first, _ in first })
        var result: [CGWindowID: CGImage] = [:]
        for window in windows {
            guard !Task.isCancelled else { return [:] }
            guard let scWindow = byID[window.id], let image = await capture(scWindow) else { continue }
            result[window.id] = image
        }
        return result
    }

    @available(macOS 14, *)
    private static func capture(_ scWindow: SCWindow) async -> CGImage? {
        let filter = SCContentFilter(desktopIndependentWindow: scWindow)
        let config = SCStreamConfiguration()
        // Cap the captured size — the thumbnail is small, and full window resolutions
        // would waste memory/time.
        let frame = scWindow.frame
        let maxDim: CGFloat = 800
        let scale = min(1, maxDim / max(frame.width, frame.height, 1))
        config.width = max(1, Int(frame.width * scale))
        config.height = max(1, Int(frame.height * scale))
        config.showsCursor = false
        return try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
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

    /// Window titles keyed by `CGWindowID` via Accessibility (empty without AX trust).
    /// Lets the names view show real titles without Screen Recording.
    static func titles(forPID pid: pid_t) -> [CGWindowID: String] {
        guard AXIsProcessTrusted(), let getWindow = Self.getWindowFn else { return [:] }
        let app = AXUIElementCreateApplication(pid)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value) == .success,
              let axWindows = value as? [AXUIElement] else { return [:] }
        var result: [CGWindowID: String] = [:]
        for ax in axWindows {
            var wid = CGWindowID(0)
            guard getWindow(ax, &wid) == .success else { continue }
            var titleValue: CFTypeRef?
            if AXUIElementCopyAttributeValue(ax, kAXTitleAttribute as CFString, &titleValue) == .success,
               let title = titleValue as? String, !title.isEmpty {
                result[wid] = title
            }
        }
        return result
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
