import Foundation
#if canImport(LiveryKit)
import LiveryKit
#else
import LiveryCore
#endif

/// A shareable bundle of Jetty's visual settings — exported/imported as a small
/// `.json` file and applied with one click, plus a set of built-in themes. Mirrors
/// Zap's preset model and can also **import Zap and Invoque themes** (see
/// `decode(from:)`), so looks can be shared across the apps. See PLAN.md §9.
struct AppearancePreset: Codable, Equatable, Identifiable {
    var name: String
    var material: DockMaterial
    var tintHex: String
    var gradientHex: String
    var gradientAngle: Double
    var backgroundOpacity: Double
    var iconSize: Double
    var tileSpacing: Double
    var cornerRadius: Double
    var magnificationEnabled: Bool
    var magnification: Double
    var indicatorStyle: IndicatorStyle
    var indicatorHex: String
    var showLabels: Bool
    /// Whether the per-tile accent glow is on — the one Appearance-pane setting that
    /// used to escape the shareable preset, so a theme silently lost it round-trip (F-M8).
    var accentGlow: Bool
    /// Foreground color of the Jetty-menu dock glyph (separate from the background tint).
    var glyphHex: String
    // Retro flourishes (Zap parity)
    var decorationStyle: String
    var decorationPosition: String
    var decorationOpacity: Double
    var decorationSize: Double
    var crtEnabled: Bool
    var crtIntensity: Double
    /// Optional so older and built-in themes do not unexpectedly replace widget styles.
    var clockFace: ClockFaceStyle?
    var clockFaceZoom: Double?
    var systemMonitorStyle: SystemMonitorStyle?
    var systemMonitorShowNetwork: Bool?

    var id: String { name }

    init(name: String,
         material: DockMaterial,
         tintHex: String,
         gradientHex: String,
         gradientAngle: Double,
         backgroundOpacity: Double,
         iconSize: Double,
         tileSpacing: Double,
         cornerRadius: Double,
         magnificationEnabled: Bool,
         magnification: Double,
         indicatorStyle: IndicatorStyle,
         indicatorHex: String,
         showLabels: Bool,
         accentGlow: Bool = Preferences.Default.accentGlow,
         glyphHex: String = Preferences.Default.glyphHex,
         decorationStyle: String = "none",
         decorationPosition: String = "topTrailing",
         decorationOpacity: Double = 1,
         decorationSize: Double = 12,
         crtEnabled: Bool = false,
         crtIntensity: Double = 0.5,
         clockFace: ClockFaceStyle? = nil,
         clockFaceZoom: Double? = nil,
         systemMonitorStyle: SystemMonitorStyle? = nil,
         systemMonitorShowNetwork: Bool? = nil) {
        self.name = name
        self.material = material
        self.tintHex = tintHex
        self.gradientHex = gradientHex
        self.gradientAngle = gradientAngle
        self.backgroundOpacity = backgroundOpacity
        self.iconSize = iconSize
        self.tileSpacing = tileSpacing
        self.cornerRadius = cornerRadius
        self.magnificationEnabled = magnificationEnabled
        self.magnification = magnification
        self.indicatorStyle = indicatorStyle
        self.indicatorHex = indicatorHex
        self.showLabels = showLabels
        self.accentGlow = accentGlow
        self.glyphHex = glyphHex
        self.decorationStyle = decorationStyle
        self.decorationPosition = decorationPosition
        self.decorationOpacity = decorationOpacity
        self.decorationSize = decorationSize
        self.crtEnabled = crtEnabled
        self.crtIntensity = crtIntensity
        self.clockFace = clockFace
        self.clockFaceZoom = clockFaceZoom
        self.systemMonitorStyle = systemMonitorStyle
        self.systemMonitorShowNetwork = systemMonitorShowNetwork
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Preferences.Default.self
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? "Imported"
        // Tolerate an *unknown* enum raw value, not just a missing key: `decodeIfPresent`
        // throws `dataCorrupted` on a present-but-unrecognized value (e.g. a material a
        // future Jetty added), which failed the whole import with a misleading "not a
        // theme" error. Fall back to the default instead, matching DockItem's decode and
        // this decoder's own "never fails" contract (F-M8).
        material = ((try? c.decodeIfPresent(DockMaterial.self, forKey: .material)) ?? nil) ?? d.material
        tintHex = try c.decodeIfPresent(String.self, forKey: .tintHex) ?? d.tintHex
        gradientHex = try c.decodeIfPresent(String.self, forKey: .gradientHex) ?? d.gradientHex
        gradientAngle = try c.decodeIfPresent(Double.self, forKey: .gradientAngle) ?? d.gradientAngle
        backgroundOpacity = try c.decodeIfPresent(Double.self, forKey: .backgroundOpacity) ?? d.backgroundOpacity
        iconSize = try c.decodeIfPresent(Double.self, forKey: .iconSize) ?? d.iconSize
        tileSpacing = try c.decodeIfPresent(Double.self, forKey: .tileSpacing) ?? d.tileSpacing
        cornerRadius = try c.decodeIfPresent(Double.self, forKey: .cornerRadius) ?? d.cornerRadius
        magnificationEnabled = try c.decodeIfPresent(Bool.self, forKey: .magnificationEnabled) ?? d.magnificationEnabled
        magnification = try c.decodeIfPresent(Double.self, forKey: .magnification) ?? d.magnification
        indicatorStyle = ((try? c.decodeIfPresent(IndicatorStyle.self, forKey: .indicatorStyle)) ?? nil) ?? d.indicatorStyle
        indicatorHex = try c.decodeIfPresent(String.self, forKey: .indicatorHex) ?? d.indicatorHex
        showLabels = try c.decodeIfPresent(Bool.self, forKey: .showLabels) ?? d.showLabels
        accentGlow = try c.decodeIfPresent(Bool.self, forKey: .accentGlow) ?? d.accentGlow
        glyphHex = try c.decodeIfPresent(String.self, forKey: .glyphHex) ?? d.glyphHex
        decorationStyle = try c.decodeIfPresent(String.self, forKey: .decorationStyle) ?? d.decorationStyle.rawValue
        decorationPosition = try c.decodeIfPresent(String.self, forKey: .decorationPosition) ?? d.decorationPosition.rawValue
        decorationOpacity = try c.decodeIfPresent(Double.self, forKey: .decorationOpacity) ?? d.decorationOpacity
        decorationSize = try c.decodeIfPresent(Double.self, forKey: .decorationSize) ?? d.decorationSize
        crtEnabled = try c.decodeIfPresent(Bool.self, forKey: .crtEnabled) ?? d.crtEnabled
        crtIntensity = try c.decodeIfPresent(Double.self, forKey: .crtIntensity) ?? d.crtIntensity
        if let raw = (try? c.decodeIfPresent(String.self, forKey: .clockFace)) ?? nil {
            clockFace = ClockFaceStyle.stored(raw)
        } else {
            clockFace = nil
        }
        clockFaceZoom = try? c.decodeIfPresent(Double.self, forKey: .clockFaceZoom)
        if let raw = (try? c.decodeIfPresent(String.self, forKey: .systemMonitorStyle)) ?? nil {
            systemMonitorStyle = SystemMonitorStyle(rawValue: raw)
        } else {
            systemMonitorStyle = nil
        }
        systemMonitorShowNetwork = try? c.decodeIfPresent(Bool.self, forKey: .systemMonitorShowNetwork)
    }

    private enum CodingKeys: String, CodingKey {
        case name, material, tintHex, gradientHex, gradientAngle, backgroundOpacity
        case iconSize, tileSpacing, cornerRadius, magnificationEnabled, magnification
        case indicatorStyle, indicatorHex, showLabels, accentGlow, glyphHex
        case decorationStyle, decorationPosition, decorationOpacity, decorationSize, crtEnabled, crtIntensity
        case clockFace, clockFaceZoom, systemMonitorStyle, systemMonitorShowNetwork
    }

    // MARK: Import (Jetty, Zap or Invoque format)

    /// Decodes a theme from JSON: Jetty's own format, or a **Zap** or
    /// **Invoque** theme file, recognised and read by Livery's shared
    /// `ThemeSnapshot`. Jetty's own decoder is fully tolerant (it never
    /// fails; defaults fill any gap), so the snapshot's format decides which
    /// reader runs. JSON the snapshot does not recognise as a theme is
    /// rejected rather than imported as an all-defaults preset, so importing
    /// the wrong file surfaces an error instead of a silent swap (M27).
    static func decode(from data: Data) -> AppearancePreset? {
        guard let theme = ThemeSnapshot(themeData: data) else { return nil }
        if theme.format == .jetty {
            return try? JSONDecoder().decode(AppearancePreset.self, from: data)
        }
        return AppearancePreset(importing: theme)
    }

    /// Maps a sibling's theme onto Jetty's settings, with Jetty's defaults
    /// for the dock layout, magnification, indicator style and widgets it
    /// does not have. The sibling's selection highlight becomes the
    /// running-app indicator color, as Jetty's Zap import always did.
    /// Jetty has no setting for the sibling's label color.
    /// Values are validated and clamped later, when the preset is applied.
    init(importing theme: ThemeSnapshot) {
        let d = Preferences.Default.self
        let fallbackName = theme.format == .zap ? "Imported (Zap)" : "Imported (Invoque)"
        self.init(
            name: theme.name ?? fallbackName,
            material: theme.material ?? d.material,
            tintHex: theme.tintHex ?? d.tintHex,
            gradientHex: theme.gradientHex ?? d.gradientHex,
            gradientAngle: theme.gradientAngle ?? d.gradientAngle,
            backgroundOpacity: theme.backgroundOpacity ?? d.backgroundOpacity,
            iconSize: theme.iconSize ?? d.iconSize,
            tileSpacing: d.tileSpacing,
            cornerRadius: theme.cornerRadius ?? d.cornerRadius,
            magnificationEnabled: d.magnificationEnabled,
            magnification: d.magnification,
            indicatorStyle: d.indicatorStyle,
            indicatorHex: theme.highlightHex ?? d.indicatorHex,
            showLabels: theme.showsLabels ?? d.showLabels,
            accentGlow: theme.adaptiveAccent ?? d.accentGlow,
            glyphHex: d.glyphHex,
            decorationStyle: (theme.decorationStyle ?? d.decorationStyle).rawValue,
            decorationPosition: (theme.decorationPosition ?? d.decorationPosition).rawValue,
            decorationOpacity: theme.decorationOpacity ?? d.decorationOpacity,
            decorationSize: theme.decorationSize ?? d.decorationSize,
            crtEnabled: theme.crtEnabled ?? d.crtEnabled,
            crtIntensity: theme.crtIntensity ?? d.crtIntensity)
    }

    // MARK: Built-in themes

    static let builtIns: [AppearancePreset] = [
        AppearancePreset(name: "Tahoe Glass", material: .liquidGlass, tintHex: "#0A7AFF",
                         gradientHex: "#3A3A3C", gradientAngle: 0, backgroundOpacity: 0.55,
                         iconSize: 52, tileSpacing: 8, cornerRadius: 22,
                         magnificationEnabled: true, magnification: 1.5,
                         indicatorStyle: .dot, indicatorHex: "#FFFFFF", showLabels: false),
        AppearancePreset(name: "Clear", material: .glassClear, tintHex: "#FFFFFF",
                         gradientHex: "#FFFFFF", gradientAngle: 0, backgroundOpacity: 0.4,
                         iconSize: 48, tileSpacing: 6, cornerRadius: 20,
                         magnificationEnabled: false, magnification: 1.3,
                         indicatorStyle: .underline, indicatorHex: "#0A84FF", showLabels: false,
                         glyphHex: "#1C1C1E"),
        AppearancePreset(name: "Graphite", material: .solid, tintHex: "#1C1C1E",
                         gradientHex: "#2C2C2E", gradientAngle: 0, backgroundOpacity: 0.85,
                         iconSize: 48, tileSpacing: 8, cornerRadius: 16,
                         magnificationEnabled: true, magnification: 1.4,
                         indicatorStyle: .bar, indicatorHex: "#0A84FF", showLabels: false),
        AppearancePreset(name: "Vapor", material: .gradient, tintHex: "#FF6AD5",
                         gradientHex: "#8795E8", gradientAngle: 60, backgroundOpacity: 0.7,
                         iconSize: 50, tileSpacing: 10, cornerRadius: 24,
                         magnificationEnabled: true, magnification: 1.6,
                         indicatorStyle: .dot, indicatorHex: "#FFFFFF", showLabels: false,
                         decorationStyle: "vaporwave", decorationPosition: "topTrailing",
                         decorationOpacity: 1, decorationSize: 12, crtEnabled: true, crtIntensity: 0.5),
        AppearancePreset(name: "ZX Night", material: .gradient, tintHex: "#0B0B1A",
                         gradientHex: "#1A1140", gradientAngle: 20, backgroundOpacity: 0.8,
                         iconSize: 50, tileSpacing: 8, cornerRadius: 14,
                         magnificationEnabled: true, magnification: 1.5,
                         indicatorStyle: .dot, indicatorHex: "#00AEEF", showLabels: false,
                         decorationStyle: "zxSpectrum", decorationPosition: "topTrailing",
                         decorationOpacity: 1, decorationSize: 12, crtEnabled: true, crtIntensity: 0.5),
        AppearancePreset(name: "Amiga", material: .solid, tintHex: "#1A1A1A",
                         gradientHex: "#2C2C2C", gradientAngle: 0, backgroundOpacity: 0.6,
                         iconSize: 52, tileSpacing: 8, cornerRadius: 16,
                         magnificationEnabled: true, magnification: 1.5,
                         indicatorStyle: .bar, indicatorHex: "#FF6F00", showLabels: false,
                         decorationStyle: "amigaPixel", decorationPosition: "topTrailing",
                         decorationOpacity: 0.2, decorationSize: 30, crtEnabled: true, crtIntensity: 0.7),
    ]
}
