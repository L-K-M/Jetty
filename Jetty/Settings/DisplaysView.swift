import SwiftUI
import AppKit

/// Per-display dock placement — the headline "position it per display" feature
/// (MF-1). Each connected display can override the global position (edge ×
/// alignment × offset × inset); displays without an override follow General.
/// Overrides are keyed by stable display UUID via `DisplayRegistry`. See PLAN.md §5.
struct DisplaysView: View {
    @ObservedObject var store: DockStore
    @ObservedObject var preferences: Preferences
    let registry: DisplayRegistry

    private struct ScreenEntry: Identifiable { let id: String; let name: String }

    var body: some View {
        Form {
            Section {
                Text("Every connected display gets its own dock. Turn a display's dock off below, or give it a custom edge and alignment. Jetty always keeps at least one dock, so turning a display off has no effect while it's the only one connected.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            ForEach(screenEntries) { entry in
                Section(entry.name) {
                    Toggle("Show dock on this display", isOn: shownBinding(entry.id))
                    if store.isDisplayDisabled(forDisplayUUID: entry.id) {
                        Text("No dock will show here — unless this becomes the only connected display, so you're never left without a dock.")
                            .font(.caption).foregroundStyle(.secondary)
                    } else {
                        Toggle("Custom position for this display", isOn: overrideBinding(entry.id))
                        if store.anchorOverride(forDisplayUUID: entry.id) != nil {
                            Picker("Edge", selection: edgeBinding(entry.id)) {
                                ForEach(DockEdge.allCases) { Text($0.label).tag($0) }
                            }
                            Picker("Alignment", selection: alignmentBinding(entry.id)) {
                                ForEach(DockAlignment.allCases) { Text($0.label).tag($0) }
                            }
                            HStack {
                                Text("Offset")
                                Slider(value: offsetBinding(entry.id), in: -600...600)
                                Text("\(Int(anchor(for: entry.id).offset))").monospacedDigit().frame(width: 44, alignment: .trailing)
                            }
                            HStack {
                                Text("Edge inset")
                                Slider(value: insetBinding(entry.id), in: 0...80)
                                Text("\(Int(anchor(for: entry.id).inset))").monospacedDigit().frame(width: 44, alignment: .trailing)
                            }
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    // MARK: Screens

    private var screenEntries: [ScreenEntry] {
        NSScreen.screens.enumerated().map { index, screen in
            let uuid = registry.key(for: screen)
            let name: String
            if #available(macOS 14.0, *) { name = screen.localizedName } else { name = "Display \(index + 1)" }
            return ScreenEntry(id: uuid, name: name)
        }
    }

    // MARK: Bindings

    private func anchor(for uuid: String) -> DockAnchor {
        store.anchorOverride(forDisplayUUID: uuid) ?? preferences.defaultAnchor(forDisplayUUID: uuid)
    }

    private func write(_ uuid: String, _ transform: (inout DockAnchor) -> Void) {
        var a = anchor(for: uuid)
        transform(&a)
        a.displayUUID = uuid
        store.setAnchor(a, forDisplayUUID: uuid)
    }

    /// Whether this display shows a dock — the inverse of the stored "disabled" opt-out,
    /// so the toggle reads "Show dock on this display" and defaults to on for every screen.
    private func shownBinding(_ uuid: String) -> Binding<Bool> {
        Binding(
            get: { !store.isDisplayDisabled(forDisplayUUID: uuid) },
            set: { shown in store.setDisplayDisabled(!shown, forDisplayUUID: uuid) })
    }

    private func overrideBinding(_ uuid: String) -> Binding<Bool> {
        Binding(
            get: { store.anchorOverride(forDisplayUUID: uuid) != nil },
            set: { on in
                if on {
                    var a = preferences.defaultAnchor(forDisplayUUID: uuid)
                    a.displayUUID = uuid
                    store.setAnchor(a, forDisplayUUID: uuid)
                } else {
                    store.clearAnchor(forDisplayUUID: uuid)
                }
            })
    }

    private func edgeBinding(_ uuid: String) -> Binding<DockEdge> {
        Binding(get: { anchor(for: uuid).edge }, set: { v in write(uuid) { $0.edge = v } })
    }
    private func alignmentBinding(_ uuid: String) -> Binding<DockAlignment> {
        Binding(get: { anchor(for: uuid).alignment }, set: { v in write(uuid) { $0.alignment = v } })
    }
    private func offsetBinding(_ uuid: String) -> Binding<Double> {
        Binding(get: { anchor(for: uuid).offset }, set: { v in write(uuid) { $0.offset = v } })
    }
    private func insetBinding(_ uuid: String) -> Binding<Double> {
        Binding(get: { anchor(for: uuid).inset }, set: { v in write(uuid) { $0.inset = v } })
    }
}
