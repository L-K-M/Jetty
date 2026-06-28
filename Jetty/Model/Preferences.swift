import Foundation
import SwiftUI
import ServiceManagement

/// User-facing settings, backed by `UserDefaults`.
///
/// An `ObservableObject` so SwiftUI settings views (and the dock) update live. A
/// custom `UserDefaults` can be injected for tests. Numeric values are clamped on
/// write so corrupted storage can't break the UI. Mirrors Zap's `Preferences`.
final class Preferences: ObservableObject {

    static let shared = Preferences()

    private let defaults: UserDefaults

    // MARK: Defaults

    enum Default {
        // Appearance
        static let material = DockMaterial.liquidGlass
        static let tintHex = "#0A7AFF"
        static let gradientHex = "#3A3A3C"
        static let gradientAngle = 0.0
        static let backgroundOpacity = 0.55
        static let iconSize = 52.0
        static let tileSpacing = 8.0
        static let cornerRadius = 22.0
        static let magnificationEnabled = true
        static let magnification = 1.5
        static let indicatorStyle = IndicatorStyle.dot
        static let indicatorHex = "#FFFFFF"
        static let showLabels = false
        static let accentGlow = true
        static let windowPreviewMode = WindowPreviewMode.names
        // Position
        static let edge = DockEdge.bottom
        static let alignment = DockAlignment.center
        static let offset = 0.0
        static let inset = 0.0
        // Behavior
        static let autoHide = true
        static let revealTrigger = RevealTrigger.both
        static let revealDelayMs = 60.0
        static let hideDelayMs = 350.0
        static let displayScope = DisplayScope.mainOnly
        static let showRunningApps = true
        static let manageSystemDock = true
        static let animationMs = 140.0
        // Decorations / CRT (Zap-style retro flourishes)
        static let decorationStyle = DecorationStyle.none
        static let decorationPosition = DecorationPosition.topTrailing
        static let decorationOpacity = 1.0
        static let decorationSize = 12.0
        static let crtEnabled = false
        static let crtIntensity = 0.5
        // Clock widget
        static let clockShowDate = true
        static let clockShowSeconds = false
        static let clockUse24Hour = false
        static let clockShowWeekday = false
        static let clockAnalog = false
        // Jetty Menu tile
        static let jettyMenuSymbol = JettyMenuGlyph.fallback
        // Hotkeys
        static let toggleHotkey = HotkeyBinding.defaultToggle
        static let menuHotkey = HotkeyBinding.defaultMenu
        // Info widgets (ND-3)
        static let worldClockTimeZone = "Europe/London"
        static let pomodoroMinutes = 25.0
        static let weatherLatitude = 0.0
        static let weatherLongitude = 0.0
        static let weatherUseCelsius = true
    }

    private enum Key {
        static let material = "material"
        static let tintHex = "tintHex"
        static let gradientHex = "gradientHex"
        static let gradientAngle = "gradientAngle"
        static let backgroundOpacity = "backgroundOpacity"
        static let iconSize = "iconSize"
        static let tileSpacing = "tileSpacing"
        static let cornerRadius = "cornerRadius"
        static let magnificationEnabled = "magnificationEnabled"
        static let magnification = "magnification"
        static let indicatorStyle = "indicatorStyle"
        static let indicatorHex = "indicatorHex"
        static let showLabels = "showLabels"
        static let accentGlow = "accentGlow"
        static let windowPreviewMode = "windowPreviewMode"
        static let edge = "edge"
        static let alignment = "alignment"
        static let offset = "offset"
        static let inset = "inset"
        static let autoHide = "autoHide"
        static let revealTrigger = "revealTrigger"
        static let revealDelayMs = "revealDelayMs"
        static let hideDelayMs = "hideDelayMs"
        static let displayScope = "displayScope"
        static let showRunningApps = "showRunningApps"
        static let manageSystemDock = "manageSystemDock"
        static let animationMs = "animationMs"
        static let decorationStyle = "decorationStyle"
        static let decorationPosition = "decorationPosition"
        static let decorationOpacity = "decorationOpacity"
        static let decorationSize = "decorationSize"
        static let crtEnabled = "crtEnabled"
        static let crtIntensity = "crtIntensity"
        static let clockShowDate = "clockShowDate"
        static let clockShowSeconds = "clockShowSeconds"
        static let clockUse24Hour = "clockUse24Hour"
        static let clockShowWeekday = "clockShowWeekday"
        static let clockAnalog = "clockAnalog"
        static let jettyMenuSymbol = "jettyMenuSymbol"
        static let toggleHotkey = "toggleHotkey"
        static let menuHotkey = "menuHotkey"
        static let worldClockTimeZone = "worldClockTimeZone"
        static let pomodoroMinutes = "pomodoroMinutes"
        static let weatherLatitude = "weatherLatitude"
        static let weatherLongitude = "weatherLongitude"
        static let weatherUseCelsius = "weatherUseCelsius"
    }

    // MARK: Appearance

    @Published var material: DockMaterial { didSet { defaults.set(material.rawValue, forKey: Key.material) } }
    @Published var tintHex: String { didSet { defaults.set(tintHex, forKey: Key.tintHex) } }
    @Published var gradientHex: String { didSet { defaults.set(gradientHex, forKey: Key.gradientHex) } }
    @Published var gradientAngle: Double { didSet { defaults.set(gradientAngle, forKey: Key.gradientAngle) } }
    @Published var backgroundOpacity: Double { didSet { defaults.set(backgroundOpacity, forKey: Key.backgroundOpacity) } }
    @Published var iconSize: Double { didSet { defaults.set(iconSize, forKey: Key.iconSize) } }
    @Published var tileSpacing: Double { didSet { defaults.set(tileSpacing, forKey: Key.tileSpacing) } }
    @Published var cornerRadius: Double { didSet { defaults.set(cornerRadius, forKey: Key.cornerRadius) } }
    @Published var magnificationEnabled: Bool { didSet { defaults.set(magnificationEnabled, forKey: Key.magnificationEnabled) } }
    @Published var magnification: Double { didSet { defaults.set(magnification, forKey: Key.magnification) } }
    @Published var indicatorStyle: IndicatorStyle { didSet { defaults.set(indicatorStyle.rawValue, forKey: Key.indicatorStyle) } }
    @Published var indicatorHex: String { didSet { defaults.set(indicatorHex, forKey: Key.indicatorHex) } }
    @Published var showLabels: Bool { didSet { defaults.set(showLabels, forKey: Key.showLabels) } }
    @Published var accentGlow: Bool { didSet { defaults.set(accentGlow, forKey: Key.accentGlow) } }
    @Published var windowPreviewMode: WindowPreviewMode { didSet { defaults.set(windowPreviewMode.rawValue, forKey: Key.windowPreviewMode) } }

    // MARK: Position

    @Published var edge: DockEdge { didSet { defaults.set(edge.rawValue, forKey: Key.edge) } }
    @Published var alignment: DockAlignment { didSet { defaults.set(alignment.rawValue, forKey: Key.alignment) } }
    @Published var offset: Double { didSet { defaults.set(offset, forKey: Key.offset) } }
    @Published var inset: Double { didSet { defaults.set(inset, forKey: Key.inset) } }

    // MARK: Behavior

    @Published var autoHide: Bool { didSet { defaults.set(autoHide, forKey: Key.autoHide) } }
    @Published var revealTrigger: RevealTrigger { didSet { defaults.set(revealTrigger.rawValue, forKey: Key.revealTrigger) } }
    @Published var revealDelayMs: Double { didSet { defaults.set(revealDelayMs, forKey: Key.revealDelayMs) } }
    @Published var hideDelayMs: Double { didSet { defaults.set(hideDelayMs, forKey: Key.hideDelayMs) } }
    @Published var displayScope: DisplayScope { didSet { defaults.set(displayScope.rawValue, forKey: Key.displayScope) } }
    @Published var showRunningApps: Bool { didSet { defaults.set(showRunningApps, forKey: Key.showRunningApps) } }
    @Published var manageSystemDock: Bool { didSet { defaults.set(manageSystemDock, forKey: Key.manageSystemDock) } }
    @Published var animationMs: Double { didSet { defaults.set(animationMs, forKey: Key.animationMs) } }

    // MARK: Decorations / CRT

    @Published var decorationStyle: DecorationStyle { didSet { defaults.set(decorationStyle.rawValue, forKey: Key.decorationStyle) } }
    @Published var decorationPosition: DecorationPosition { didSet { defaults.set(decorationPosition.rawValue, forKey: Key.decorationPosition) } }
    @Published var decorationOpacity: Double { didSet { defaults.set(decorationOpacity, forKey: Key.decorationOpacity) } }
    @Published var decorationSize: Double { didSet { defaults.set(decorationSize, forKey: Key.decorationSize) } }
    @Published var crtEnabled: Bool { didSet { defaults.set(crtEnabled, forKey: Key.crtEnabled) } }
    @Published var crtIntensity: Double { didSet { defaults.set(crtIntensity, forKey: Key.crtIntensity) } }

    // MARK: Clock widget

    @Published var clockShowDate: Bool { didSet { defaults.set(clockShowDate, forKey: Key.clockShowDate) } }
    @Published var clockShowSeconds: Bool { didSet { defaults.set(clockShowSeconds, forKey: Key.clockShowSeconds) } }
    @Published var clockUse24Hour: Bool { didSet { defaults.set(clockUse24Hour, forKey: Key.clockUse24Hour) } }
    @Published var clockShowWeekday: Bool { didSet { defaults.set(clockShowWeekday, forKey: Key.clockShowWeekday) } }
    @Published var clockAnalog: Bool { didSet { defaults.set(clockAnalog, forKey: Key.clockAnalog) } }
    @Published var jettyMenuSymbol: String { didSet { defaults.set(jettyMenuSymbol, forKey: Key.jettyMenuSymbol) } }

    // MARK: Hotkeys

    @Published var toggleHotkey: HotkeyBinding { didSet { defaults.set(toggleHotkey.jsonString, forKey: Key.toggleHotkey) } }
    @Published var menuHotkey: HotkeyBinding { didSet { defaults.set(menuHotkey.jsonString, forKey: Key.menuHotkey) } }

    // MARK: Info widgets

    @Published var worldClockTimeZone: String { didSet { defaults.set(worldClockTimeZone, forKey: Key.worldClockTimeZone) } }
    @Published var pomodoroMinutes: Double { didSet { defaults.set(pomodoroMinutes, forKey: Key.pomodoroMinutes) } }
    @Published var weatherLatitude: Double { didSet { defaults.set(weatherLatitude, forKey: Key.weatherLatitude) } }
    @Published var weatherLongitude: Double { didSet { defaults.set(weatherLongitude, forKey: Key.weatherLongitude) } }
    @Published var weatherUseCelsius: Bool { didSet { defaults.set(weatherUseCelsius, forKey: Key.weatherUseCelsius) } }

    // MARK: Launch at login

    /// Backed by `SMAppService`, not `UserDefaults`. Setting it (un)registers the
    /// login item; reading reflects the live service status.
    @Published var launchAtLogin: Bool {
        didSet {
            guard oldValue != launchAtLogin else { return }
            applyLaunchAtLogin(launchAtLogin)
        }
    }

    // MARK: Init

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let d = Default.self

        func string(_ key: String, _ fallback: String) -> String { defaults.string(forKey: key) ?? fallback }
        func double(_ key: String, _ fallback: Double) -> Double { defaults.object(forKey: key) == nil ? fallback : defaults.double(forKey: key) }
        func bool(_ key: String, _ fallback: Bool) -> Bool { defaults.object(forKey: key) == nil ? fallback : defaults.bool(forKey: key) }

        material = DockMaterial(rawValue: string(Key.material, d.material.rawValue)) ?? d.material
        tintHex = string(Key.tintHex, d.tintHex)
        gradientHex = string(Key.gradientHex, d.gradientHex)
        gradientAngle = double(Key.gradientAngle, d.gradientAngle)
        backgroundOpacity = Self.clamp(double(Key.backgroundOpacity, d.backgroundOpacity), 0, 1)
        iconSize = Self.clamp(double(Key.iconSize, d.iconSize), 24, 128)
        tileSpacing = Self.clamp(double(Key.tileSpacing, d.tileSpacing), 0, 32)
        cornerRadius = Self.clamp(double(Key.cornerRadius, d.cornerRadius), 0, 40)
        magnificationEnabled = bool(Key.magnificationEnabled, d.magnificationEnabled)
        magnification = Self.clamp(double(Key.magnification, d.magnification), 1, 2.5)
        indicatorStyle = IndicatorStyle(rawValue: string(Key.indicatorStyle, d.indicatorStyle.rawValue)) ?? d.indicatorStyle
        indicatorHex = string(Key.indicatorHex, d.indicatorHex)
        showLabels = bool(Key.showLabels, d.showLabels)
        accentGlow = bool(Key.accentGlow, d.accentGlow)
        windowPreviewMode = WindowPreviewMode(rawValue: string(Key.windowPreviewMode, d.windowPreviewMode.rawValue)) ?? d.windowPreviewMode

        edge = DockEdge(rawValue: string(Key.edge, d.edge.rawValue)) ?? d.edge
        alignment = DockAlignment(rawValue: string(Key.alignment, d.alignment.rawValue)) ?? d.alignment
        offset = double(Key.offset, d.offset)
        inset = DockAnchor.clampInset(double(Key.inset, d.inset))

        autoHide = bool(Key.autoHide, d.autoHide)
        revealTrigger = RevealTrigger(rawValue: string(Key.revealTrigger, d.revealTrigger.rawValue)) ?? d.revealTrigger
        revealDelayMs = Self.clamp(double(Key.revealDelayMs, d.revealDelayMs), 0, 1000)
        hideDelayMs = Self.clamp(double(Key.hideDelayMs, d.hideDelayMs), 0, 2000)
        displayScope = DisplayScope(rawValue: string(Key.displayScope, d.displayScope.rawValue)) ?? d.displayScope
        showRunningApps = bool(Key.showRunningApps, d.showRunningApps)
        manageSystemDock = bool(Key.manageSystemDock, d.manageSystemDock)
        animationMs = Self.clamp(double(Key.animationMs, d.animationMs), 0, 600)

        decorationStyle = DecorationStyle(rawValue: string(Key.decorationStyle, d.decorationStyle.rawValue)) ?? d.decorationStyle
        decorationPosition = DecorationPosition(rawValue: string(Key.decorationPosition, d.decorationPosition.rawValue)) ?? d.decorationPosition
        decorationOpacity = Self.clamp(double(Key.decorationOpacity, d.decorationOpacity), 0, 1)
        decorationSize = Self.clamp(double(Key.decorationSize, d.decorationSize), 4, 80)
        crtEnabled = bool(Key.crtEnabled, d.crtEnabled)
        crtIntensity = Self.clamp(double(Key.crtIntensity, d.crtIntensity), 0, 1)
        clockShowDate = bool(Key.clockShowDate, d.clockShowDate)
        clockShowSeconds = bool(Key.clockShowSeconds, d.clockShowSeconds)
        clockUse24Hour = bool(Key.clockUse24Hour, d.clockUse24Hour)
        clockShowWeekday = bool(Key.clockShowWeekday, d.clockShowWeekday)
        clockAnalog = bool(Key.clockAnalog, d.clockAnalog)
        jettyMenuSymbol = string(Key.jettyMenuSymbol, d.jettyMenuSymbol)
        toggleHotkey = HotkeyBinding.decode(defaults.string(forKey: Key.toggleHotkey), fallback: d.toggleHotkey)
        menuHotkey = HotkeyBinding.decode(defaults.string(forKey: Key.menuHotkey), fallback: d.menuHotkey)
        worldClockTimeZone = string(Key.worldClockTimeZone, d.worldClockTimeZone)
        pomodoroMinutes = Self.clamp(double(Key.pomodoroMinutes, d.pomodoroMinutes), 1, 180)
        weatherLatitude = Self.clamp(double(Key.weatherLatitude, d.weatherLatitude), -90, 90)
        weatherLongitude = Self.clamp(double(Key.weatherLongitude, d.weatherLongitude), -180, 180)
        weatherUseCelsius = bool(Key.weatherUseCelsius, d.weatherUseCelsius)

        launchAtLogin = (SMAppService.mainApp.status == .enabled)
    }

    // MARK: Derived

    var tintColor: Color { Color(hexString: tintHex) }
    var gradientColor: Color { Color(hexString: gradientHex) }
    var indicatorColor: Color { Color(hexString: indicatorHex) }

    /// The effective magnification factor (1.0 when disabled).
    var effectiveMagnification: CGFloat { magnificationEnabled ? CGFloat(magnification) : 1.0 }

    /// The global default anchor for a display that has no stored override.
    func defaultAnchor(forDisplayUUID uuid: String) -> DockAnchor {
        DockAnchor(displayUUID: uuid, edge: edge, alignment: alignment, offset: offset, inset: inset)
    }

    // MARK: Presets

    /// Captures the current appearance into a named preset (for Export…).
    func currentAppearancePreset(name: String = "My Theme") -> AppearancePreset {
        AppearancePreset(name: name, material: material, tintHex: tintHex, gradientHex: gradientHex,
                         gradientAngle: gradientAngle, backgroundOpacity: backgroundOpacity, iconSize: iconSize,
                         tileSpacing: tileSpacing, cornerRadius: cornerRadius, magnificationEnabled: magnificationEnabled,
                         magnification: magnification, indicatorStyle: indicatorStyle, indicatorHex: indicatorHex,
                         showLabels: showLabels,
                         decorationStyle: decorationStyle.rawValue, decorationPosition: decorationPosition.rawValue,
                         decorationOpacity: decorationOpacity, decorationSize: decorationSize,
                         crtEnabled: crtEnabled, crtIntensity: crtIntensity)
    }

    /// Applies a preset's appearance values (leaves position/behavior untouched).
    func apply(_ preset: AppearancePreset) {
        material = preset.material
        tintHex = preset.tintHex
        gradientHex = preset.gradientHex
        gradientAngle = preset.gradientAngle
        backgroundOpacity = Self.clamp(preset.backgroundOpacity, 0, 1)
        iconSize = Self.clamp(preset.iconSize, 24, 128)
        tileSpacing = Self.clamp(preset.tileSpacing, 0, 32)
        cornerRadius = Self.clamp(preset.cornerRadius, 0, 40)
        magnificationEnabled = preset.magnificationEnabled
        magnification = Self.clamp(preset.magnification, 1, 2.5)
        indicatorStyle = preset.indicatorStyle
        indicatorHex = preset.indicatorHex
        showLabels = preset.showLabels
        decorationStyle = DecorationStyle(rawValue: preset.decorationStyle) ?? .none
        decorationPosition = DecorationPosition(rawValue: preset.decorationPosition) ?? .topTrailing
        decorationOpacity = Self.clamp(preset.decorationOpacity, 0, 1)
        decorationSize = Self.clamp(preset.decorationSize, 4, 80)
        crtEnabled = preset.crtEnabled
        crtIntensity = Self.clamp(preset.crtIntensity, 0, 1)
    }

    // MARK: Launch at login

    func refreshLaunchAtLoginStatus() {
        let enabled = (SMAppService.mainApp.status == .enabled)
        if enabled != launchAtLogin {
            // Update the published value without re-triggering registration.
            launchAtLoginSilently(enabled)
        }
    }

    private func applyLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled { try SMAppService.mainApp.register() }
            } else {
                if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() }
            }
        } catch {
            NSLog("Jetty: launch-at-login \(enabled ? "register" : "unregister") failed: \(error.localizedDescription)")
            launchAtLoginSilently(SMAppService.mainApp.status == .enabled)
        }
    }

    private func launchAtLoginSilently(_ value: Bool) {
        // Assigning to the @Published property re-runs didSet, so guard there on
        // oldValue == newValue (it no-ops). This keeps the UI in sync with reality.
        if launchAtLogin != value { launchAtLogin = value }
    }

    // MARK: Helpers

    static func clamp(_ value: Double, _ lower: Double, _ upper: Double) -> Double {
        guard value.isFinite else { return lower }
        return Swift.min(Swift.max(value, lower), upper)
    }
}
