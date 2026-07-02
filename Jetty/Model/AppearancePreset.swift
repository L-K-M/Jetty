import Foundation

/// A shareable bundle of Jetty's visual settings — exported/imported as a small
/// `.json` file and applied with one click, plus a set of built-in themes. Mirrors
/// Zap's preset model and can also **import a Zap theme** (see `decode(from:)`), so
/// looks can be shared across the two apps. See PLAN.md §9.
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
         crtIntensity: Double = 0.5) {
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
    }

    private enum CodingKeys: String, CodingKey {
        case name, material, tintHex, gradientHex, gradientAngle, backgroundOpacity
        case iconSize, tileSpacing, cornerRadius, magnificationEnabled, magnification
        case indicatorStyle, indicatorHex, showLabels, accentGlow, glyphHex
        case decorationStyle, decorationPosition, decorationOpacity, decorationSize, crtEnabled, crtIntensity
    }

    // MARK: Import (Jetty or Zap format)

    /// Decodes a theme from JSON, accepting both Jetty's own format and a **Zap**
    /// theme file (its field names differ — `backgroundColorHex`, `useGradientBackground`,
    /// `highlightColorHex`, `showAppName`, …). Since Jetty's own decoder is fully
    /// tolerant (it never fails — defaults fill any gap), we sniff the raw keys to
    /// tell the two formats apart and only fall back to Jetty otherwise.
    static func decode(from data: Data) -> AppearancePreset? {
        if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            let hasJettyKeys = obj["material"] != nil || obj["tintHex"] != nil || obj["indicatorStyle"] != nil
            let hasZapKeys = obj["backgroundColorHex"] != nil || obj["useGradientBackground"] != nil || obj["showAppName"] != nil
            if !hasJettyKeys, hasZapKeys, let zap = try? JSONDecoder().decode(ZapTheme.self, from: data) {
                return zap.asJettyPreset
            }
            // A JSON object with none of the recognized keys isn't a theme — reject it
            // rather than let the fully-tolerant decoder return an all-defaults preset,
            // so importing a wrong file surfaces an error instead of a silent swap (M27).
            guard hasJettyKeys else { return nil }
        }
        return try? JSONDecoder().decode(AppearancePreset.self, from: data)
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

// MARK: - Zap theme interop

/// The subset of a **Zap** appearance preset Jetty understands, so a `.json` theme
/// exported from Zap can be imported here. Field names match Zap's `AppearancePreset`.
private struct ZapTheme: Decodable {
    var name: String?
    var backgroundColorHex: String?
    var useGradientBackground: Bool?
    var gradientColorHex: String?
    var gradientAngle: Double?
    var decorationStyle: String?
    var decorationPosition: String?
    var decorationOpacity: Double?
    var decorationSize: Double?
    var crtEnabled: Bool?
    var crtIntensity: Double?
    var highlightColorHex: String?
    var backgroundOpacity: Double?
    var iconSize: Double?
    var cornerRadius: Double?
    var showAppName: Bool?

    var asJettyPreset: AppearancePreset {
        AppearancePreset(
            name: name ?? "Imported (Zap)",
            material: (useGradientBackground == true) ? .gradient : .solid,
            tintHex: backgroundColorHex ?? Preferences.Default.tintHex,
            gradientHex: gradientColorHex ?? Preferences.Default.gradientHex,
            gradientAngle: gradientAngle ?? 0,
            backgroundOpacity: backgroundOpacity ?? Preferences.Default.backgroundOpacity,
            iconSize: iconSize ?? Preferences.Default.iconSize,
            tileSpacing: Preferences.Default.tileSpacing,
            cornerRadius: cornerRadius ?? Preferences.Default.cornerRadius,
            magnificationEnabled: Preferences.Default.magnificationEnabled,
            magnification: Preferences.Default.magnification,
            indicatorStyle: Preferences.Default.indicatorStyle,
            indicatorHex: highlightColorHex ?? Preferences.Default.indicatorHex,
            showLabels: showAppName ?? false,
            decorationStyle: decorationStyle ?? "none",
            decorationPosition: decorationPosition ?? "topTrailing",
            decorationOpacity: decorationOpacity ?? 1,
            decorationSize: decorationSize ?? 12,
            crtEnabled: crtEnabled ?? false,
            crtIntensity: crtIntensity ?? 0.5)
    }
}
