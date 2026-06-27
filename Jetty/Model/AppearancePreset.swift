import Foundation

/// A shareable bundle of Jetty's visual settings — exported/imported as a small
/// `.json` file and applied with one click, plus a set of built-in themes. Mirrors
/// Zap's preset model. Capturing/applying goes through `Preferences`. See PLAN.md §9.
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
         showLabels: Bool) {
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
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Preferences.Default.self
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? "Imported"
        material = try c.decodeIfPresent(DockMaterial.self, forKey: .material) ?? d.material
        tintHex = try c.decodeIfPresent(String.self, forKey: .tintHex) ?? d.tintHex
        gradientHex = try c.decodeIfPresent(String.self, forKey: .gradientHex) ?? d.gradientHex
        gradientAngle = try c.decodeIfPresent(Double.self, forKey: .gradientAngle) ?? d.gradientAngle
        backgroundOpacity = try c.decodeIfPresent(Double.self, forKey: .backgroundOpacity) ?? d.backgroundOpacity
        iconSize = try c.decodeIfPresent(Double.self, forKey: .iconSize) ?? d.iconSize
        tileSpacing = try c.decodeIfPresent(Double.self, forKey: .tileSpacing) ?? d.tileSpacing
        cornerRadius = try c.decodeIfPresent(Double.self, forKey: .cornerRadius) ?? d.cornerRadius
        magnificationEnabled = try c.decodeIfPresent(Bool.self, forKey: .magnificationEnabled) ?? d.magnificationEnabled
        magnification = try c.decodeIfPresent(Double.self, forKey: .magnification) ?? d.magnification
        indicatorStyle = try c.decodeIfPresent(IndicatorStyle.self, forKey: .indicatorStyle) ?? d.indicatorStyle
        indicatorHex = try c.decodeIfPresent(String.self, forKey: .indicatorHex) ?? d.indicatorHex
        showLabels = try c.decodeIfPresent(Bool.self, forKey: .showLabels) ?? d.showLabels
    }

    private enum CodingKeys: String, CodingKey {
        case name, material, tintHex, gradientHex, gradientAngle, backgroundOpacity
        case iconSize, tileSpacing, cornerRadius, magnificationEnabled, magnification
        case indicatorStyle, indicatorHex, showLabels
    }

    // MARK: Built-ins

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
                         indicatorStyle: .underline, indicatorHex: "#0A84FF", showLabels: false),
        AppearancePreset(name: "Graphite", material: .solid, tintHex: "#1C1C1E",
                         gradientHex: "#2C2C2E", gradientAngle: 0, backgroundOpacity: 0.85,
                         iconSize: 48, tileSpacing: 8, cornerRadius: 16,
                         magnificationEnabled: true, magnification: 1.4,
                         indicatorStyle: .bar, indicatorHex: "#0A84FF", showLabels: false),
        AppearancePreset(name: "Vapor", material: .gradient, tintHex: "#FF6AD5",
                         gradientHex: "#8795E8", gradientAngle: 60, backgroundOpacity: 0.7,
                         iconSize: 50, tileSpacing: 10, cornerRadius: 24,
                         magnificationEnabled: true, magnification: 1.6,
                         indicatorStyle: .dot, indicatorHex: "#FFFFFF", showLabels: false),
    ]
}
