# AGENTS.md

Guidance for AI coding agents working in the **Jetty** repository.

## What Jetty Is

Jetty is a fast, native, **auto-hiding dock for macOS Tahoe (26)** that stands in for
the system Dock — with free-form positioning (any edge × leading/center/trailing ×
offset/inset, per display), deep visual control (native Liquid Glass + shareable
presets), and built-in extras (a family of live info tiles — clock, battery, weather,
world clock, Pomodoro, CPU/RAM, now-playing — folder-stack popovers, and a
Start-menu-style **Jetty Menu** / command bar with app search, calculator,
unit/currency conversion, and power commands). It is the third app in the L-K-M family alongside
**Zap** (app switcher) and **MacDring** (edge-tab launcher) and reuses their house
style. See `PLAN.md` for the full design and the feasibility analysis; `REVIEW.md`
for the current status and open backlog; `README.md` for the user view.

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
(The one exception so far: the Objective-C MediaRemote bridge needed a
`SWIFT_OBJC_BRIDGING_HEADER` build setting on the app target; pure-Swift files need none.)

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
- `Apps/` — `RunningAppsModel` (NSWorkspace running apps), `AppLauncher`, and
  `TrashMonitor` (DispatchSource watch so the Trash tile reflects empty/full live).
- `SystemDock/` — `SystemDockController` (hide/re-assert/restore the real Dock).
- `Dock/` — `DockController` (the brain), `DockPanelController` (per-display
  auto-hiding panel), `DockModel` (pure tile merge), `DockView`/`DockTileView`,
  `MagnificationCurve` (pure), `EdgeHoverMonitor`.
- `Widgets/` — the live info tiles: `ClockWidgetView` (+ pure `ClockFormatter`),
  `BatteryWidgetView`, `WeatherWidgetView` (+ `WeatherService`), `WorldClockWidgetView`,
  `PomodoroWidgetView` (+ `PomodoroTimer`), `SystemMonitorWidgetView` (+ `SystemStats`),
  `NowPlayingWidgetView` (+ `NowPlayingService`). Keep the formatters/parsers pure.
- `Stacks/` — the folder-stack popover: pure `FolderStack` (ordering/geometry/content)
  + `FolderStackController` (the floating panel).
- `Menu/` — the Jetty Menu / command bar (`JettyMenuController`/`View`/`Model`,
  `AppIndex`, `RecentAppsStore`, and the pure `AppSearch`, `ExpressionEvaluator`,
  `UnitConverter`, `CurrencyService`, `MenuCommand`, `PowerCommands`).
- `Hotkeys/` — `CarbonHotkey`, `KeyCodes`, `AccessibilityAuthorizer` (for later features).
- `Settings/` — the SwiftUI settings panes (General/Appearance/Items/Displays/Widgets/
  Menu/Permissions/About) + window controller and `HotkeyRecorder`.
- `Updates/` — the GitHub self-updater (reused from Zap).
- `MediaRemote/` — the isolated Objective-C MediaRemote bridge (`MediaRemoteBridge`)
  behind `Jetty-Bridging-Header.h`, used only by the opt-in now-playing tile.
- `Windows/` — the opt-in window peek: `AppWindows` (CGWindowList listing + AX
  raise/minimize), `WindowPeek` + `WindowPeekController` (the hover popover panel).
  The default window-name mode is permission-free; live thumbnails need Screen
  Recording; raising/minimizing a specific window needs Accessibility.
- `Common/` — `VisualEffectView`, `GlassBackground` (Liquid Glass + fallback),
  `ActivationPolicy`, `LRUImageCache`/`IconCache`, `TileAccent` (dominant-color glow),
  `Poof`, and the retro decorations (`PanelDecoration`, `BoingBallDecoration`,
  `CRTScreenOverlay`).

## Conventions

- Follow the Swift API Design Guidelines; one type per file; `// MARK:` sections.
- Avoid force-unwraps outside tests.
- Keep the logic backbone **pure** (no global state, no windowing) so it stays
  unit-testable: `DockLayout`, `MagnificationCurve`, `ClockFormatter`, `AppSearch`,
  `DockModel.makeSlots`/`makeTiles`, `PowerCommand` mapping, `ExpressionEvaluator`,
  `UnitConverter`, `CurrencyService` parsing, `MenuCommand.match`, `FolderStack`
  geometry/ordering, `SystemStats`/`WeatherService` formatting, `HotkeyBinding`,
  `NowPlayingService.parse`, and `SemanticVersion`.

## Critical Constraints

- **No scary permissions for the core dock.** Apps/launch/icons use `NSWorkspace`;
  reveal uses a global **mouse** monitor (allowed) + Carbon hotkeys. **Never** add a
  *global key* monitor or a `CGEventTap` to the core path — that needs Accessibility
  and breaks the no-permission promise. Window peeking / live previews have shipped
  as **opt-in** features behind their own permissions (Accessibility / Screen Recording).
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
- **Keep `LSUIElement = true`**; **Settings** temporarily goes `.regular` and reverts
  to `.accessory` on close (shared `ActivationPolicy` guard). The **Jetty Menu** does
  *not* switch activation policy — it uses a key, non-activating panel and briefly
  activates the app to focus its search field, handing activation back on close (no
  Dock-icon flash). Don't "fix" the menu to toggle `.regular`.

## Testing Notes

- Unit-test the pure logic: `DockLayout` geometry, `DockModel.makeSlots`/`makeTiles`,
  `MagnificationCurve`, `ClockFormatter`, `AppSearch`, `PowerCommand` mapping,
  `ExpressionEvaluator`, `UnitConverter`, `CurrencyService`, `MenuCommand`,
  `FolderStack`, `SystemStats`/`WeatherService`, `NowPlayingService.parse`,
  `HotkeyBinding`, `UpdateDownloader` filename sanitizing, Codable + forward-compat,
  `Preferences` clamping, `AppearancePreset` round-trip, `SemanticVersion`,
  `GitHubRelease`.
- `AppDelegate.applicationDidFinishLaunching` is guarded by `isRunningTests`, so the
  test host doesn't spin up panels or hide the Dock.
- Window placement, multi-monitor, reveal/auto-hide, Dock-hide, Liquid Glass,
  drag-and-drop, and the power commands need a **real GUI session** and are verified
  manually.

## Do / Don't

- **Do** update `PLAN.md` when the design changes, keep `REVIEW.md`'s status/backlog
  current, and keep `README.md` in sync.
- **Do** assume Developer ID + notarization (not the App Store) — the sandbox can't
  grant the Accessibility access the later window features need.
- **Don't** add heavy dependencies; prefer system frameworks.
- **Don't** persist absolute window frames, reserve screen space, or let a dock/menu
  panel activate the app (except the Jetty Menu's deliberate focus hand-off).
- **Don't** reach for private APIs in the core. The one private-API use that has
  shipped — the **MediaRemote** bridge behind the **opt-in** now-playing tile — is
  isolated under `MediaRemote/`, `dlopen`-based, and **fails closed** (returns nil →
  plain music glyph) when unavailable; keep any future private-API use the same way
  (isolated, opt-in, fail-closed). Others contemplated for *later* features
  (`_AXUIElementGetWindow`, `AXStatusLabel`) must likewise be weak-imported and isolated.
