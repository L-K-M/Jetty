# AGENTS.md

Guidance for AI coding agents working in the **Jetty** repository.

## What Jetty Is

Jetty is a fast, native, **auto-hiding dock for macOS Tahoe (26)** that stands in for
the system Dock — with free-form positioning (any edge × leading/center/trailing ×
offset/inset, per display), deep visual control (native Liquid Glass + shareable
presets), and built-in extras (a date/time tile and a Start-menu-style **Jetty Menu**
with app search + power commands). It is the third app in the L-K-M family alongside
**Zap** (app switcher) and **MacDring** (edge-tab launcher) and reuses their house
style. See `PLAN.md` for the full design and the feasibility analysis; `README.md`
for the user view.

## The one load-bearing design decision

Jetty does **not** reserve screen space and does **not** move other apps' windows.
It is **hidden by default** and floats its dock **over** content on reveal (pointer
at the edge, or a hotkey). This is deliberate: there is no public API to shrink
`NSScreen.visibleFrame`, and the window-nudging workaround other docks use is fragile
and needs Accessibility. Opting out of reservation makes the **core dock
permission-free**. Don't reintroduce a reservation/nudging dependency in the core.

## Tech Stack

- **Language:** Swift (Swift 5 language mode — `SWIFT_VERSION = 5.0`).
- **UI:** SwiftUI for the dock, Jetty Menu, and Settings; AppKit for windowing
  (`NSPanel`, `NSStatusItem`, `NSVisualEffectView`, and `NSGlassEffectView` on macOS 26).
- **System APIs:** `NSWorkspace`/`NSRunningApplication` (apps — no permission),
  `CGDisplayCreateUUIDFromDisplayID` (stable display identity), global **mouse**
  monitor + Carbon `RegisterEventHotKey` (reveal triggers — no Accessibility),
  AppleEvents/`NSAppleScript` (Jetty Menu power commands), `SMAppService` (launch at
  login). The system Dock is hidden via the `com.apple.dock` `autohide`/
  `autohide-delay` defaults + `killall Dock` (reversible, no SIP).
- **Persistence:** a Codable `DockDocument` as JSON in
  `~/Library/Application Support/Jetty/dock.json`; app-wide settings in `UserDefaults`.
- **Min target:** macOS 13 (Liquid Glass gated `@available(macOS 26, *)` with an
  `NSVisualEffectView` fallback). **Build with Xcode 26** for Liquid Glass.
- **App type:** menu-bar agent (`LSUIElement = true`, `.accessory` policy, no Dock
  icon of its own), **non-sandboxed**, Developer ID + notarization (no App Store).

## Build & Run

The Xcode project uses **file-system-synchronized groups**, so new files under
`Jetty/` or `JettyTests/` are picked up automatically — no `project.pbxproj` edits.

```bash
# Build
xcodebuild -project Jetty.xcodeproj -scheme Jetty -configuration Debug build

# Run unit tests (pure logic: layout, tile merge, magnification, clock, search, prefs)
xcodebuild -project Jetty.xcodeproj -scheme Jetty -destination 'platform=macOS' test
```

`scripts/build.sh` / `scripts/release.sh` are thin stubs over the shared
`lkm-build` / `lkm-release` engine (the `release-tool` repo). Prefer building/running
from Xcode during development so the panels, reveal, and Dock-hide behave in a real
GUI session.

## Module Layout

Mirrors `PLAN.md §11`:

- `Model/` — Codable model (`DockDocument`, `DockItem`, `DockAnchor`, `DockEdge`/
  `DockAlignment`, `AppearancePreset`), `Preferences`, `ColorHex`, the UI enums.
- `Store/` — `DockStore` (JSON load/save, atomic/debounced, `.bak`), `BookmarkResolver`.
- `Screens/` — `DisplayRegistry` (UUID mapping) and the pure `DockLayout` math.
- `Apps/` — `RunningAppsModel` (NSWorkspace running apps), `AppLauncher`.
- `SystemDock/` — `SystemDockController` (hide/re-assert/restore the real Dock).
- `Dock/` — `DockController` (the brain), `DockPanelController` (per-display
  auto-hiding panel), `DockModel` (pure tile merge), `DockView`/`DockTileView`,
  `MagnificationCurve` (pure), `EdgeHoverMonitor`.
- `Widgets/` — `ClockWidgetView` + the pure `ClockFormatter`.
- `Menu/` — the Jetty Menu (`JettyMenuController`/`View`/`Model`, `AppIndex`, the pure
  `AppSearch`, `PowerCommands`).
- `Hotkeys/` — `CarbonHotkey`, `KeyCodes`, `AccessibilityAuthorizer` (for later features).
- `Settings/` — the SwiftUI settings panes + window controller.
- `Updates/` — the GitHub self-updater (reused from Zap).
- `Common/` — `VisualEffectView`, `GlassBackground` (Liquid Glass + fallback),
  `ActivationPolicy`, `LRUImageCache`.

## Conventions

- Follow the Swift API Design Guidelines; one type per file; `// MARK:` sections.
- Avoid force-unwraps outside tests.
- Keep `DockLayout`, `MagnificationCurve`, `ClockFormatter`, `AppSearch`,
  `DockModel.makeTiles`, and `PowerCommand`'s mapping **pure** (no global state, no
  windowing) so they stay unit-testable — they're the logic backbone.

## Critical Constraints

- **No scary permissions for the core dock.** Apps/launch/icons use `NSWorkspace`;
  reveal uses a global **mouse** monitor (allowed) + Carbon hotkeys. **Never** add a
  *global key* monitor or a `CGEventTap` to the core path — that needs Accessibility
  and breaks the no-permission promise. Window peeking / live previews are *later*,
  *opt-in* features behind their own permissions.
- **Dock/menu panels must stay non-activating** (`NSPanel` with `.nonactivatingPanel`).
  Clicking a tile must never steal focus from the user's frontmost app. (The Jetty
  Menu is the one exception — it briefly activates to focus its search field and
  hands activation back on close.)
- **Don't reserve screen space or move other apps' windows.** Jetty floats over
  content and auto-hides. (See "the one load-bearing design decision" above.)
- **Never kill/inject the system Dock as a strategy.** Hide it with the `autohide` +
  long `autohide-delay` defaults trick; `killall Dock` only once to apply; always
  offer **Restore System Dock**; re-assert on launch/wake (Tahoe glitches auto-hide).
- **Stable restore:** persist a dock's placement as a display **UUID** + edge +
  alignment + offset/inset — never raw pixels. All placement goes through
  `DockLayout` against `NSScreen.visibleFrame`.
- **Show on every Space / over fullscreen:** keep `collectionBehavior` =
  `[.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]` on the panels.
- **Liquid Glass is macOS 26 only.** Gate it `@available(macOS 26, *)` and fall back
  to `NSVisualEffectView`; honor Reduce Transparency.
- **Keep `LSUIElement = true`**; Settings/Jetty-Menu temporarily go `.regular` and
  revert to `.accessory` on close (shared `ActivationPolicy` guard).

## Testing Notes

- Unit-test the pure logic: `DockLayout` geometry, `DockModel.makeTiles`,
  `MagnificationCurve`, `ClockFormatter`, `AppSearch`, `PowerCommand` mapping,
  Codable + forward-compat, `Preferences` clamping, `AppearancePreset` round-trip,
  `SemanticVersion`, `GitHubRelease`.
- `AppDelegate.applicationDidFinishLaunching` is guarded by `isRunningTests`, so the
  test host doesn't spin up panels or hide the Dock.
- Window placement, multi-monitor, reveal/auto-hide, Dock-hide, Liquid Glass,
  drag-and-drop, and the power commands need a **real GUI session** and are verified
  manually.

## Do / Don't

- **Do** update `PLAN.md` when the design changes, and keep `README.md` in sync.
- **Do** assume Developer ID + notarization (not the App Store) — the sandbox can't
  grant the Accessibility access the later window features need.
- **Don't** add heavy dependencies; prefer system frameworks.
- **Don't** persist absolute window frames, reserve screen space, or let a dock/menu
  panel activate the app (except the Jetty Menu's deliberate focus hand-off).
- **Don't** reach for private APIs in the core. The only ones ever contemplated
  (`_AXUIElementGetWindow`, `AXStatusLabel`) belong to *later* features and must be
  weak-imported, isolated, and fall back to public APIs.
