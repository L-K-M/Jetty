# AGENTS.md

Guidance for AI coding agents working in the **Jetty** repository.

## How it works (and what it can't do)

macOS doesn't let *any* app truly replace or remove the Dock — it's a protected system
process that also runs Mission Control and window minimizing. So Jetty does what every
reliable third-party dock does: it **hides** Apple's Dock (auto-hide + a long reveal
delay) and runs its own **alongside** it, using only public APIs (no SIP changes, no
code injection). One click in **Settings → General → Restore System Dock** puts the
real Dock back. See [`PLAN.md`](PLAN.md) for the full feasibility analysis.

Because Jetty floats over content instead of reserving space, maximized windows aren't
pushed aside — which is exactly why it auto-hides and needs no Accessibility permission
to run.

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
Jetty is macOS-only today; the Ubuntu/Linux port research and its work plan live in
`docs/linux-port.md` and `docs/linux-port-plan.md`.

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
  `DockAlignment`, `AppearancePreset`), `Preferences`, the UI enums, and the colour
  pair: pure `RGBA8` (the `#RRGGBB[AA]` storage format) plus `ColorHex`'s thin
  `NSColor`/`Color` bridge over it.
- `Store/` — `DockStore` (JSON load/save, atomic/debounced, `.bak`), `BookmarkResolver`
  (bookmarks are Darwin-only; it falls back to the stored absolute path elsewhere).
- `Screens/` — `DisplayRegistry` (UUID mapping), the pure `DockLayout` math, and
  `LayerShellPlacement` (that math expressed as Wayland layer-shell anchors/margins;
  unused on macOS, see `docs/linux-port-plan.md` §JP-03).
- `Apps/` — `RunningAppsModel` (NSWorkspace running apps) over the portable
  `RunningAppInfo` value type, `TrashLocations` (Finder's Trash on Darwin, the XDG
  trash elsewhere), `AppLauncher`, and
  `TrashMonitor` (DispatchSource watch so the Trash tile reflects empty/full live).
- `SystemDock/` — `SystemDockController` (hide/re-assert/restore the real Dock).
- `Dock/` — `DockController` (the brain), `DockPanelController` (per-display
  auto-hiding panel), the pure `DockTileMerge` (tile/slot merge) plus `DockModel`
  (the observable wrapper that adds cached icon resolution), the `DockTile`/
  `DockSlot` value types, `DockView`/`DockTileView`,
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
  `DockTileMerge.makeSlots`/`makeTiles` (its one impure need, the Trash-URL check,
  is an injected parameter), `PowerCommand` mapping, `ExpressionEvaluator`,
  `UnitConverter`, `CurrencyService` parsing, `MenuCommand.match`, `FolderStack`
  geometry/ordering, `SystemStats`/`WeatherService` formatting, `HotkeyBinding`,
  `NowPlayingService.parse`, and `SemanticVersion`.

## Dependencies

Exactly one: [`PictKit`](https://github.com/L-K-M/Pict), a first-party SwiftPM
package holding the shared icon store and resolution ladder that Zap, Top Drawer
and the Pict editor also use. Jetty **reads** it and writes nothing to it — all
editing lives in Pict, which needs no permissions and can be sandboxed.

Icon precedence in `DockModel.icon(for:)`, top rung first:

1. the item's own `customIconPath` — existing behaviour, still wins
2. the shared store — an icon set in Pict, Zap or Top Drawer
3. the bundle's own un-masked artwork
4. `NSWorkspace.icon(forFile:)`

Rung 1 staying on top is what makes this invisible on upgrade, and it is also a
feature: two tiles pointing at one app are allowed to differ.

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

- Unit-test the pure logic: `DockLayout` geometry, `DockTileMerge.makeSlots`/`makeTiles`,
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

<!-- shared-rules:start -->

## Working practices

- Follow explicit task instructions over the default workflow below.
- Before editing, inspect the branch and working tree, fetch remote updates,
  and fast-forward where safe. Never overwrite existing work to update.
- Resolve ambiguity before making consequential changes. State low-risk
  assumptions; ask when scope, safety, or expected behavior is unclear.
- Keep changes focused. Do not modify unrelated code, formatting, or comments.
- Prefer surgical edits over whole-file rewrites when the result is equivalent.
- Stage only intended files. Inspect the diff before committing.

## Communication

- Be concise, factual, and direct. Preserve necessary context and uncertainty.
- Avoid praise, motivational filler, emojis, and em dashes in new prose.
- Address the reader directly in user-facing copy.
- Report what was verified and what remains unverified. Never imply that an
  unavailable check passed.

## Code design

- Prefer early returns and shallow nesting. Separate logical blocks with
  blank lines.
- Use descriptive constants or enums for meaningful or repeated values.
  Use existing standard definitions for protocol/specification constants.
  Keep obvious, one-off values inline.
- Use enums for behavioral modes that would otherwise require ambiguous
  boolean arguments.
- Default members to private. Widen visibility only for required consumers,
  and review the change as an API design decision.
- Follow the repository's declared dependency boundaries. UI and controllers
  must use application services rather than directly accessing databases,
  subprocesses, sockets, or other low-level mechanisms.
- Encapsulate low-level mechanics behind domain-oriented interfaces.
- Reuse genuinely shared logic. Avoid speculative abstractions and layers
  that only forward calls.
- Prefer pure functions for business rules and immutable data where practical.
  Isolate side effects; document non-obvious state ownership or synchronization.
- Explain non-obvious intent, constraints, and tradeoffs in comments.
  Do not narrate obvious code. Add examples or diagrams when they clarify it.

## Validation and errors

- Validate untrusted input at entry points. Where practical, represent valid
  states in types and enforce persistent invariants in database schemas.
- Represent absence and failure explicitly.
- Use assertions for internal programming invariants, not external-input
  validation or required runtime error handling.
- Prefer explicit, actionable errors over silent failure or undocumented
  fallback. Document intentional recovery behavior.
- Never report a skipped or failed operation as successful.

## Bug fixes

1. Identify the root cause and define an observable success criterion.
2. Add a regression test and observe the relevant failure before fixing it.
3. Implement the fix and observe the test passing.
4. Check surrounding behavior for regressions and architectural consistency.

If an automated regression test is impractical, document the reproduction
and verification procedure. State any inability to reproduce the failure.

## Verification

- Run relevant tests and lint after changes.
- Choose coverage by affected behavior and risk, not patch size.
- Use integration or end-to-end tests for critical workflows and boundaries;
  test isolated business rules at the lowest effective level.
- Run broader suites for cross-cutting or high-risk changes, and the full
  required release checks before releasing.
- Validate the requested command, options, platform, and configuration.
  Unrelated green CI is not proof that the reported problem is fixed.
- Recheck after the final edit. Distinguish local checks from CI results.

## Commit messages

- Use a capitalized, imperative subject without a final period.
- Target 50 characters; never exceed 72.
- Separate the subject and body with one blank line.
- Wrap body text at 72 characters.
- Explain what changed and why. Leave implementation mechanics to the code.

## Implementation and review

Unless explicitly instructed otherwise:

1. Work on a focused branch and open a PR against main.
2. Inspect CI results and completed review feedback for the latest commit.
   A successful reviewer job does not mean the review found no problems.
3. Address important findings or explain why they do not apply. Handle minor
   findings according to the stopping rules below.
4. Evaluate each fix in the surrounding project, add regression coverage,
   and rerun affected checks before pushing.
5. Repeat until a stopping criterion is met.
6. Merge without asking again once the stopping criterion is met, required
   checks pass on the latest commit, and no unresolved blockers or required
   human review requests remain.

### Automated review stopping rules

Judge findings by verified impact, not the reviewer's severity label.
Important findings concern correctness, security, data loss, broken builds,
or materially degraded behavior/performance.

Track completed review rounds and consecutive rounds without important
findings. Reruns of the same revision and integration failures do not count.

- No applicable actionable feedback: finish immediately.
- First minor-only round: optionally fix worthwhile, low-risk findings.
  Do not manufacture another push merely to obtain another review.
- Two consecutive rounds without important findings: stop responding to
  automated nitpicks, even if actionable minor suggestions remain.
  Defer worthwhile leftovers rather than continuing the cycle.
- A confirmed important finding resets the minor-only streak. Address it
  and verify the fix before continuing.

After ten completed rounds, enter stabilization:

- Stop optional cleanup, refactoring, and nitpick fixes.
- One completed review without confirmed important findings is sufficient
  to finish, even if minor suggestions remain.
- Continue only for confirmed important defects. If resolving them stalls,
  report the blockers rather than continuing indefinitely.

These limits end optional automated-feedback work. They do not waive
confirmed blockers, unresolved human review requests, or required checks.

### Reviewer integration failures

After two consecutive reviewer-integration failures, stop and report the
review gap. Do not treat failures as approval. An explicit user instruction
may waive review; report that waiver rather than claiming review passed.

## Completion checklist

- The requested behavior is implemented without unrelated changes.
- Relevant checks pass for the latest code.
- Important review findings are addressed or rejected with reasons.
- Deferred suggestions, remaining risks, and validation gaps are disclosed.
- The final response accurately states whether work is committed, pushed,
  and merged.

<!-- shared-rules:end -->
