import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Appearance settings: material (Liquid Glass / solid / gradient), tint, sizing,
/// magnification, indicators, and shareable presets with import/export. See
/// PLAN.md §9.
struct AppearanceView: View {
    @ObservedObject var preferences: Preferences
    @State private var importError: String?

    var body: some View {
        Form {
            Section("Material") {
                Picker("Style", selection: $preferences.material) {
                    ForEach(DockMaterial.allCases) { Text($0.label).tag($0) }
                }
                ColorPicker("Tint", selection: jettyColorBinding($preferences.tintHex))
                if preferences.material == .gradient {
                    ColorPicker("Gradient end", selection: jettyColorBinding($preferences.gradientHex))
                    HStack {
                        Text("Angle")
                        AngleDial(angleDegrees: $preferences.gradientAngle)
                        Spacer()
                    }
                }
                HStack {
                    Text("Background opacity")
                    Slider(value: $preferences.backgroundOpacity, in: 0...1)
                }
            }

            Section("Size") {
                slider("Icon size", $preferences.iconSize, 24...128, "pt")
                slider("Tile spacing", $preferences.tileSpacing, 0...32, "pt")
                slider("Corner radius", $preferences.cornerRadius, 0...40, "pt")
                Toggle("Magnify on hover", isOn: $preferences.magnificationEnabled)
                if preferences.magnificationEnabled {
                    HStack {
                        Text("Magnification")
                        Slider(value: $preferences.magnification, in: 1...2.5)
                        Text(String(format: "%.1f×", preferences.magnification))
                            .monospacedDigit().frame(width: 44, alignment: .trailing)
                    }
                }
            }

            Section("Indicators & labels") {
                Picker("Running indicator", selection: $preferences.indicatorStyle) {
                    ForEach(IndicatorStyle.allCases) { Text($0.label).tag($0) }
                }
                ColorPicker("Indicator color", selection: jettyColorBinding($preferences.indicatorHex))
                Toggle("Show name on hover", isOn: $preferences.showLabels)
            }

            Section("Presets") {
                ForEach(AppearancePreset.builtIns) { preset in
                    HStack {
                        Text(preset.name)
                        Spacer()
                        Button("Apply") { preferences.apply(preset) }
                    }
                }
                HStack {
                    Button("Export…") { exportPreset() }
                    Button("Import…") { importPreset() }
                }
                if let importError {
                    Text(importError).font(.caption).foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
    }

    private func slider(_ title: String, _ value: Binding<Double>, _ range: ClosedRange<Double>, _ unit: String) -> some View {
        HStack {
            Text(title)
            Slider(value: value, in: range)
            Text("\(Int(value.wrappedValue)) \(unit)").monospacedDigit().frame(width: 56, alignment: .trailing)
        }
    }

    // MARK: Import / export

    private func exportPreset() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "JettyTheme.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(preferences.currentAppearancePreset())
            try data.write(to: url)
        } catch {
            importError = "Export failed: \(error.localizedDescription)"
        }
    }

    private func importPreset() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let data = try Data(contentsOf: url)
            let preset = try JSONDecoder().decode(AppearancePreset.self, from: data)
            preferences.apply(preset)
            importError = nil
        } catch {
            importError = "Import failed: \(error.localizedDescription)"
        }
    }
}
