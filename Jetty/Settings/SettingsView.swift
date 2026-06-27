import SwiftUI

/// The Settings window content: one tab per pane. Mirrors Zap/MacDring.
struct SettingsView: View {
    @ObservedObject var preferences: Preferences
    @ObservedObject var store: DockStore
    let systemDock: SystemDockController
    let registry: DisplayRegistry
    @ObservedObject var updateChecker: UpdateChecker

    var body: some View {
        TabView {
            GeneralView(preferences: preferences, systemDock: systemDock)
                .tabItem { Label("General", systemImage: "gearshape") }
            AppearanceView(preferences: preferences)
                .tabItem { Label("Appearance", systemImage: "paintbrush") }
            ItemsView(store: store)
                .tabItem { Label("Items", systemImage: "square.grid.2x2") }
            DisplaysView(store: store, preferences: preferences, registry: registry)
                .tabItem { Label("Displays", systemImage: "display.2") }
            MenuView(preferences: preferences)
                .tabItem { Label("Jetty Menu", systemImage: "magnifyingglass") }
            PermissionsView()
                .tabItem { Label("Permissions", systemImage: "lock.shield") }
            AboutView(updateChecker: updateChecker)
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(minWidth: 540, minHeight: 480)
        .padding(.top, 4)
    }
}

/// A `Binding<Color>` over a hex `Binding<String>`, so SwiftUI `ColorPicker`s drive
/// the persisted hex preferences directly. Module-wide so every pane can use it.
func jettyColorBinding(_ hex: Binding<String>) -> Binding<Color> {
    Binding(get: { Color(hexString: hex.wrappedValue) },
            set: { hex.wrappedValue = $0.hexString })
}
