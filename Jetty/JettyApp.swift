import AppKit

/// Program entry point.
///
/// Jetty is a menu-bar agent (`LSUIElement`), so it runs as an `.accessory` app
/// with no Dock icon of its own. A plain `NSApplication` lifecycle (rather than the
/// SwiftUI `App` scene) keeps full control over the borderless dock panels.
@main
enum JettyMain {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}
