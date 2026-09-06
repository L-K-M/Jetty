# Jetty Linux Port — Implementation Plan (executor edition)

*Written 2026-09-06. The step-by-step execution plan for the research in
[`linux-port.md`](linux-port.md). Written for an AI coding agent working
autonomously in a Linux environment: it front-loads decisions, names files, and
prefers boring, verifiable techniques over clever ones. Read `linux-port.md` first
for the big picture.*

Work items are numbered **`JP-01` … `JP-35`**. Two of them land in the **Pict** repo
(`JP-12`, `JP-13`); the rest land in **Jetty**.

---

## Part 0 — Ground rules

**The governing ground rules are Part 0 of the cross-repo
[Linux Port implementation plan](https://github.com/L-K-M/TopDrawer/blob/main/docs/linux-port/implementation-plan.md)
in the Top Drawer repo.** They apply to every PR here unchanged: one PR at a time in
item order; keep macOS green as the prime directive; the standard cross-platform
idioms; the weak-model doctrine (parse files and call stable CLIs before writing C
interop); the PR lifecycle (implement → open → subscribe + arm an hourly check-in →
babysit to steady state → merge with both CI jobs green); resumability by PR title;
and when to stop and ask.

Four deltas specific to Jetty:

- **`SWIFT_VERSION = 5.0`.** Both new manifests use swift-tools 5.9 so Linux CI is
  neither stricter nor looser than `xcodebuild`.
- **File-system-synchronized Xcode groups are a trap here.** Any new `.swift` file
  under `Jetty/` is automatically added to the macOS target. Linux-only code lives
  in `linux/`, outside `Jetty/`; the rare file that must live under `Jetty/` carries
  a whole-file `#if os(Linux)`.
- **Never run bare `xcodebuild`** in this repo — always pass `-project`, so the root
  `Package.swift` and `Jetty.xcodeproj` coexist safely. `ci.yml` and
  `scripts/build.sh` already do; confirm the shared `lkm-build` engine does too.
- **Extraction PRs are pure moves.** No behaviour change, no reformatting; the
  existing tests move with the code and must pass unchanged on both platforms.

### Prior art to copy, not reinvent

Jetty is the **third** app through this pipeline. Before writing anything, read:

| What | Where |
|---|---|
| The Linux `Package.swift` shape, path-dependency on the root package | `TopDrawer/linux/Package.swift` |
| `CGtk4` / `CGtkLayerShell` systemLibrary targets + shim headers | `TopDrawer/linux/Sources/CLibraries/` |
| A working GTK4 + layer-shell frontend | `TopDrawer/linux/Sources/topdrawer-shell/` |
| D-Bus daemon, service, systemd unit | `TopDrawer/linux/Sources/TopDrawerDaemon/`, `linux/systemd/` |
| `.deb` build script | `TopDrawer/linux/packaging/build-deb.sh` |
| Linux CI incl. building gtk4-layer-shell from source | `TopDrawer/.github/workflows/linux-ci.yml` + `.github/actions/setup-gtk4-layer-shell` |
| The Combine shim | `TopDrawer/MacDring/Common/ObservationCompat.swift` |
| `DesktopEntry` parsing, `LinuxRunningApps`, `GioTrashService`, `LinuxLauncher` | `TopDrawer/linux/Sources/TopDrawerDaemon/` |
| inotify shim + Linux watcher | `Pict/Sources/CInotify/`, `Pict/Sources/PictKit/Store/IconStoreWatcherLinux.swift` |
| Whole-file guard style, `PixelImage`, `ResolvedIconImage` | `Pict/Sources/PictKit/` |

Where a Jetty item duplicates one of these deliberately (rather than sharing it),
the PR body must say **why** — the research already argues the case for the trash
watcher and against sharing `IconStoreWatcher`.

---

## Part 1 — Foundations (CI first, so every later PR has a net)

### JP-01 · Jetty · Root `Package.swift` + `JettyCore` seed + Linux CI
**Branch** `claude/jp-01-linux-ci` · **Size** M · **Why**: `linux-port.md` §Build

- Add a root `Package.swift` (swift-tools 5.9): library target **named `Jetty`** at
  `path: "Jetty"` with `exclude: ["Resources", "MediaRemote", "Jetty.entitlements"]`
  and a curated `sources:` list; test target **`JettyTests`** at `path: "JettyTests"`
  with a curated list, so the existing `@testable import Jetty` files compile
  unmodified.
- Seed `sources:` with this exact set of **24 files**. It is not a guess: it was
  built and its tests run on Swift 6.3.3 / Ubuntu 24.04 while this plan was being
  written — **116 tests across 8 suites, 0 failures**.

  `Screens/DockLayout.swift`, `Dock/MagnificationCurve.swift`,
  `Model/`{`DockEdge`, `DockAnchor`, `DockDocument`, `DockItem`, `DockItemKind`,
  `ClockFaceStyle`, `DecorationPosition`, `DecorationStyle`, `SystemMonitorStyle`,
  `TrashIconStyle`, `PreferenceEnums`}, `Widgets/`{`ClockFormatter`,
  `ClockGeometry`, `SevenSegment`}, `Menu/`{`AppSearch`, `ExpressionEvaluator`,
  `UnitConverter`}, `Updates/`{`SemanticVersion`, `GitHubRelease`,
  `GitHubReleaseClient`, `UpdateDownloader`, `UpdateVersionComparison`}.

  Tests: `DockLayoutTests`, `MagnificationCurveTests`, `ClockFormatterTests`,
  `ClockGeometrySecondsTests`, `AppSearchTests`, `ExpressionEvaluatorTests`,
  `SemanticVersionTests`, `GitHubReleaseTests`, `UpdateVersionComparisonTests`.
- Guards needed, and no others — each one verified as necessary and sufficient by
  compiling:
  - `#if canImport(CoreGraphics) … #else import Foundation #endif` on the four files
    that import CoreGraphics for its value types: `DockLayout`,
    `MagnificationCurve`, `DockItemKind`, `ClockGeometry` (plus the same in
    `DockLayoutTests`).
  - `#if canImport(FoundationNetworking)` in `GitHubReleaseClient`,
    `UpdateDownloader`, `UpdateVersionComparison`.
  - `#if canImport(SwiftUI) … #else import Foundation #endif` on
    `DecorationPosition` and `DecorationStyle` — they import SwiftUI only for
    `Identifiable` — **plus** a `#if canImport(SwiftUI)` around
    `DecorationStyle.colors` alone (`DecorationStyle.swift:45-47`), which maps the
    pure `hexes` array through SwiftUI's `Color`. `hexes` itself stays portable.
  - `#if canImport(AppKit)` around **`DockItem`'s three classifier factories**
    (`DockItem.swift:61-89`), not around its `import AppKit`: the actual blocker is
    `fromFileURL`'s `TrashLocations.isTrashURL` call. The Codable half — which is
    what the document format needs — is fully portable. JP-04 separates them
    properly; this is the minimal guard that gets CI green today.
- **Three files the research proposed for this set do not belong in it**, each for a
  concrete reason found by compiling:
  - `Dock/DockSlot.swift` references `DockTile`, which lives in `DockModel.swift`
    and is `NSImage`-bound → **JP-06**.
  - `Model/JettyMenuGlyph.swift` validates symbol names with
    `NSImage(systemSymbolName:)` (`JettyMenuGlyph.swift:32`) — a real AppKit
    dependency, and precisely the thing JP-11's `IconName` abstraction replaces.
  - `JettyTests/DockLayoutGapTests.swift` needs `Preferences` → add it in **JP-02**,
    once the Observation shim lands.
- Add `.github/workflows/linux-ci.yml`: `container: swift:6.3-noble` (pin by digest,
  as Top Drawer does), `swift build && swift test`, on PRs and pushes to `main`.
- **Acceptance**: Linux job green with the seeded suites running; macOS CI untouched
  and green; zero diff to macOS-compiled semantics (guards only); `.xcodeproj`
  untouched.
- **Pitfalls**: don't reformat while adding guards. A `sources:` entry that doesn't
  exist produces only a warning — treat any "Invalid Source" warning as an error.
  Do **not** add `Model/Preferences.swift` or `Model/ColorHex.swift` yet (they are
  `ObservableObject` / `NSColor` — JP-02 and JP-04).

### JP-02 · Jetty · Combine compatibility shim
**Branch** `claude/jp-02-observation-compat` · **Size** S

- Copy Top Drawer's merged `ObservationCompat.swift` into `Jetty/Common/`, guarded
  so it is Linux-only and additive; macOS keeps real Combine.
- Bring `Model/Preferences.swift`, `Widgets/WeatherService.swift` and the other
  `ObservableObject` types that are otherwise portable into the `sources:` list.
- **Decline the full `@Observable` migration** and record why in the PR body:
  Jetty has 96 `@Published` / 16 `ObservableObject` but only **6** `.sink` calls;
  converting 15 types is a large macOS-visible diff for zero Linux benefit.
- **Acceptance**: `Preferences` and `WeatherService` compile and test on Linux;
  macOS diff is additive only.

---

## Part 2 — Core extraction (macOS-improving; validated by macOS CI)

*Each item is a **pure move** into `JettyCore` with its tests. Land them in order;
each is small enough to review as a move.*

### JP-03 · Jetty · Geometry core: `DockLayout` + `MagnificationCurve`
**Branch** `claude/jp-03-geometry-core` · **Size** S-M

- Move all 362 LOC of `DockLayout` and `MagnificationCurve` with `DockEdge`,
  `DockAlignment`, `DockAnchor`. They already have zero platform API.
- Add a **new pure** `DockLayout.layerShellPlacement(frame:in:edge:)` →
  `(anchorEdges, margins, exclusiveZone)`, unit-tested against the existing
  `DockLayoutTests` fixture (`CGRect(0, 0, 1000, 800)` — already per-output local
  space, so every existing assertion stays valid verbatim).
- Document the five cross-file "keep in sync" constants `DockLayout`'s doc comments
  name (separator width 12; clock resting 1.6×; LCD 1.35×; the clock edge factor)
  as `JettyCore` constants rather than duplicated literals.
- **Acceptance**: `DockLayoutTests`, `DockLayoutGapTests`, `MagnificationCurveTests`
  green on both platforms, unchanged.
- **Pitfalls**: `DockLayout` is Cocoa bottom-left-origin y-up throughout. Do **not**
  flip it here. The single deliberate flip belongs at the toolkit boundary (JP-24).

### JP-04 · Jetty · Document + store core
**Branch** `claude/jp-04-document-core` · **Size** M

- Move `DockDocument` + the `Failable<T>` lenient-decode wrapper, `DockItem`'s
  Codable half + `dedupKey` (separated from its three classifier factories),
  `DockAnchor.clampOffset`/`clampInset`.
- Generalise `DockStore`'s engine into `DocumentStore<T: Codable>`: load → decode →
  `.bak` fallback → newer-version read-only gate → debounced atomic save. **Preserve
  the semantics exactly** — they are tested and load-bearing, and a debounced
  autosave that loses the gate can destroy a user document.
- Extract `RGBA8` (`init?(hex:)` / `hexString`, ~45 LOC of pure arithmetic) out of
  the `NSColor` extension in `ColorHex.swift`, keeping the `+` rejection and the
  `#`-prefix rules; `NSColor` keeps a thin macOS-only bridge.
- **Acceptance**: `CodableModelTests`, `StoreBackupTests`, `StoreVersionTests`,
  `ColorHexTests` green on both platforms.
- **Pitfalls**: `BookmarkResolver` is Darwin-only — guard its two functions with
  `#if os(macOS)` returning `nil` on Linux; every read path already falls back to
  the sibling absolute path.

### JP-05 · Jetty · Preferences split
**Branch** `claude/jp-05-preferences` · **Size** M

- `Preferences.Default` and `Preferences.Key` are nested inside the
  `ObservableObject` class; lift them out **first**, then introduce
  `PreferencesModel` over a `KeyValueStoring` protocol carrying the clamp ranges
  (iconSize 24…128, magnification 1…2.5, cornerRadius 0…40, tileSpacing 0…32,
  revealDelayMs 0…1000, …). `UserDefaults` conforms on macOS; Linux gets an
  XDG-backed implementation later.
- **Acceptance**: `PreferencesTests` green unchanged on both platforms.

### JP-06 · Jetty · Dock model + strip geometry
**Branch** `claude/jp-06-dock-model` · **Size** M

- Move `DockModel.makeSlots`/`makeTiles` (with all three unique-id guards and Trash
  normalisation), `DockTile`/`DockSlot` value types (retyping `var icon: NSImage?`
  to PictKit's neutral handle), `DockContextMenuPlacement`, `DockContextAction`,
  `LRUImageCacheByKey` (generic over the image type).
- Extract **new** pure types out of the SwiftUI views: `DockStripLayout`
  (clockWidthFactor, contentOverflows, tileCenters, stackLocalAlong, scale),
  `DockDragPolicy` (slotExtents, the neighbour-shift rule, the index→ordered-itemID
  mapping), `DockTileGeometry` (tileWidth, the Fitts'-law padding split),
  `DockTileAccessibility.label(for:)`/`value(for:)`.
- **Acceptance**: `DockModelTests`, `DockContextMenuPlacementTests` green; new
  tests for each extracted type.
- **Pitfalls**: `DockTileGeometry.tileWidth` and `DockLayout.tileExtent` must agree —
  the existing comment says "keep in sync"; extraction is the chance to make that a
  single source of truth instead of a comment.

### JP-07 · Jetty · Reveal policy extraction
**Branch** `claude/jp-07-reveal-policy` · **Size** M · **This is the load-bearing one.**

- Extract from `DockPanelController`: `DockRevealPolicy` (`handleMouseMoved` reduced
  to a pure `(event, geometry, prefs, state) -> RevealDecision`), `DockZones` (the
  four zone predicates), `DockPanelMetrics` (`contentSize`'s magnification headroom
  budget, the compounding clock-face zoom, the hover-label headroom), `HiddenOffset`
  (`hiddenTransform` restated as `(edge, size) -> (dx, dy)` so a `CALayer` transform
  and a `GskTransform` consume the same two numbers).
- `KeepRevealedFrameTests` and `PointerOverDockContentTests` move with them and
  become the conformance suite for both platforms.
- **Acceptance**: those suites green unchanged; `DockPanelController` becomes a thin
  AppKit adapter over the policy.
- **Pitfalls**: this is where ~200 LOC of Linux code gets *avoided* later — the
  display-seam `pointerCrossedDockEdge` hysteresis exists only because a global
  mouse monitor cannot know which display's dock a pointer meant. Extract it
  faithfully now; mark it macOS-only in the doc comment rather than deleting it.

### JP-08 · Jetty · Controller policy extraction
**Branch** `claude/jp-08-controller-policy` · **Size** M-L

- Extract from `DockController`: `PreferenceWorkTiers` (the BUG-7 signature/dispatch
  as a pure `(old, new) -> Set<WorkTier>`), `DockReorder.apply(items:orderedIDs:)`,
  `TileAnchorLocator` (whose own comment admits it must be kept in sync with
  `DockView.tileCenters` — extraction de-duplicates a live drift risk),
  `HoverPreviewPolicy` (the 0.45s dwell machine), `TileMenuBuilder` (`contextActions`
  split into a pure menu *shape* plus a platform binding table), `TrashRefreshPolicy`
  (the in-flight flag, 5s reveal throttle, 0.3s watcher debounce),
  `DockSeedAndMigration.ensureRunningSentinel`, `PrimaryPressTracker`.
- `enabledTargets(base:disabled:)` is already static and tested — move it with
  `DockModelTests`' coverage.
- **Acceptance**: existing suites green; new tests for each newly-pure type (most
  are currently untested — this PR is a net test-coverage win for macOS).

### JP-09 · Jetty · Command-bar core
**Branch** `claude/jp-09-command-bar-core` · **Size** M

- Move `AppSearch` (generalising `bundleID` → `identifier`, `url` → `locator` so a
  desktop-file ID fits), `ExpressionEvaluator`, `UnitConverter` (folding its
  duplicate `scientificString` with `ExpressionEvaluator`'s),
  `CurrencyService`'s pure half behind a `RateFetching` protocol,
  `JettyMenuModel.rankedResults`/`formatCurrency`, `MenuCommand` + `match`,
  and the `PowerCommand` catalogue (`title`, `isDestructive`, `confirmationPrompt`,
  icon name) with `appleScript` demoted to a macOS-only extension.
- Refactor `activateSelection()` into a pure
  `decide(_ state: MenuState) -> MenuAction`.
- Reword the `confirmationPrompt` strings that say "your Mac".
- **Acceptance**: `AppSearchTests`, `ExpressionEvaluatorTests`, `CommandBarTests`,
  `PowerCommandTests`, `MenuGlyphAndStoreTests` green on both platforms.

### JP-10 · Jetty · Widget cores
**Branch** `claude/jp-10-widget-cores` · **Size** M

- Move `ClockFormatter`, `ClockGeometry`, `SevenSegment`, `PomodoroTimer`'s pure
  state machine, `SystemStats`' pure half (`Battery`, `batterySymbol(percent:)`,
  `isLowBattery(percent:isPlugged:)`, `normalizedLoad`), `LiveSystemStats.throughput`
  / `isLongSamplingGap` / the history ring, and `NowPlayingService.parse`'s shape
  (taking a metadata dictionary, so MPRIS can feed the same function).
- **Acceptance**: `ClockFormatterTests`, `ClockFaceTests`, `ClockGeometrySecondsTests`,
  `PomodoroTests`, `InfoWidgetTests`, `SystemMonitorPathTests`, `WeatherRetryTests`
  green on both platforms.
- **Pitfalls**: `SystemStats.swift` also holds `import IOKit.ps`,
  `memoryUsedFraction()` (mach) and `networkBytes()` (`AF_LINK`) — those stay behind
  the JP-15 seam. Only the pure half moves.

### JP-11 · Jetty · Remaining cores + the `IconName` abstraction
**Branch** `claude/jp-11-remaining-cores` · **Size** M

- Move `FolderStack`'s pure half (`orderedBefore`, `isDrillable`, `maxPanelHeight`,
  `panelSize`, `origin(for:near:dock:edge:in:)`, and a `sortAndCap` split out of
  `entries(of:)`), `FolderStackPresentationPolicy` (the 0.5s grace-hide machine),
  `HotkeyBinding`'s platform-neutral half, and `DisplayKeyAssigner` (the
  key-assignment algorithm out of `DisplayRegistry.rebuild()`, whose collision-suffix
  machinery Linux needs *more* than macOS does).
- Introduce **`IconName`** over the ~31 distinct SF Symbol names Jetty uses, on
  macOS first, with the freedesktop/Adwaita mapping table alongside. Include the two
  fallback glyphs (`powerplug.fill`, the music glyph) — the adversarial pass caught
  that the *degraded* paths are SF Symbols too.
- Add `keySymbol: String?` to `HotkeyBinding`'s Codable form so a Linux-recorded
  binding round-trips a prefs file that travels back to a Mac.
- **Acceptance**: `FolderStackTests`, `HotkeyBindingTests`, `LinkNormalizationTests`
  green on both platforms; an `IconName` table test asserting every referenced
  symbol has a mapping.

---

## Part 3 — Pict prerequisites

### JP-12 · Pict · `DesktopEntry` parser + `DesktopEntryIndex` in PictKit
**Branch** `claude/jp-12-desktop-entry-index` · **Size** M · **Repo: Pict**

- Add `Sources/PictKit/Store/DesktopEntry.swift` + `DesktopEntryIndex.swift`, next
  to the existing `DesktopEntryRewriter`/`DesktopOverrideSync`. Three apps need it
  (Jetty's app index and command bar, Top Drawer's LP-19, the Pict editor), which
  clears PictKit's "more than one app needs it" bar.
- Scan the union of `$XDG_DATA_HOME/applications`, `$XDG_DATA_DIRS/applications`,
  `/var/lib/snapd/desktop/applications` and both Flatpak export dirs — never trust
  `$XDG_DATA_DIRS` alone. Dedupe by desktop-file ID, first-wins. Honour `NoDisplay`,
  `Hidden`, `OnlyShowIn`, `NotShowIn`, `TryExec`. Resolve `Name`/`GenericName`/
  `Keywords` by the spec's locale ladder.
- Parse `Exec` per spec: quoting rules and field codes (`%f %F %u %U %i %c %k`),
  returning an argv array. **Never** build a shell string.
- Retire `DesktopOverrideSync.overrideFilename(forSystemPath:)`'s documented
  best-effort desktop-ID guess in favour of the real index.
- **Acceptance**: unit tests over hostile fixtures (quoting, embedded `%`, missing
  `Exec`, bad locale keys, symlink loops) before anything is ever executed; existing
  `DesktopOverrideSyncTests` and `DesktopEntryRewriterTests` green; macOS CI green
  (the whole target compiles on both platforms today — keep it that way).
- **Pitfalls**: this is a **public** PictKit surface and therefore a
  three-release-cadence compatibility commitment. Keep it small: an entry value
  type, an index, and a lookup. No preferences, no UI, no launching.

### JP-13 · Pict · Linux `ArtworkProviding` via icon-theme lookup
**Branch** `claude/jp-13-artwork-theme` · **Size** M · **Repo: Pict**

- This is the corpus's **LP-24a**, which Jetty now has a second reason to want.
  Implement the Linux `BundleArtworkProvider` replacement: resolve a desktop entry's
  `Icon=` through the freedesktop Icon Theme spec (index.theme inheritance,
  size/scale matching, the mandatory `hicolor` fallback), returning a `PixelImage`.
- SVG-only theme icons go through `rsvg-convert` using the corpus's verified
  fresh-empty-temp-dir sandbox recipe (there is no `--base-uri` flag; the base is the
  input file's directory).
- **Acceptance**: fixture-theme unit tests (inheritance, scale, symbolic fallback,
  a hostile SVG regression case); `IconResolverTests` still green.

---

## Part 4 — Tile data seams (tier-independent; no compositor needed)

*These are fully unit-testable and independent of the desktop wall, so they can land
before any tier decision.*

### JP-14 · Jetty · `BatteryProviding` — UPower
**Branch** `claude/jp-14-battery` · **Size** M

- Linux impl: one `Properties.GetAll` on
  `/org/freedesktop/UPower/devices/DisplayDevice` (system bus), subscribed to
  `PropertiesChanged`, with a slow poll as safety net.
- **Corrections from the adversarial pass, both load-bearing**: decide "no battery"
  from **`Type`** (0 Unknown / 1 Line Power / 2 Battery / 3 Ups), *not* `IsPresent`;
  and do **not** map `!OnBattery` to macOS's `isPlugged` — they diverge on any
  machine exposing no line-power device (a fully-charged idle battery reports
  `State=4`, so `OnBattery=false` while actually on battery), which would mis-drive
  `isLowBattery(percent:isPlugged:)`.
- Treat `PropertiesChanged` as a **delta plus an invalidated list**, never a full
  snapshot.
- Keep `/sys/class/power_supply` (filtered `type=="Battery" && scope!="Device"`) as an
  explicit fallback; note it has no per-battery "plugged" bit — that requires reading
  a separate Mains supply's `online`.
- Consider surfacing UPower's own `WarningLevel`/`BatteryLevel` rather than
  recomputing Jetty's threshold, which honours per-vendor policy.
- **Acceptance**: provider tests against a mock D-Bus service under
  `dbus-run-session`; `InfoWidgetTests`' battery assertions unchanged.

### JP-15 · Jetty · `SystemMetricsProviding` — /proc
**Branch** `claude/jp-15-system-metrics` · **Size** M

- `/proc/loadavg` (the `getloadavg` call ports with an import swap),
  `/proc/meminfo`, and a `/proc/net/dev` reader replacing the `AF_LINK` `getifaddrs`
  walk. `isCountedInterface`'s exclusion list is Darwin-specific — rewrite it for
  Linux (`lo`, `docker*`, `veth*`, `br-*`, `virbr*`, `tun*`, `tap*`) rather than
  forking the prefix array.
- **Corrections**: procfs files report `st_size == 0`, so any code that pre-sizes a
  buffer from `stat` silently reads nothing — **read to EOF**. Memory occupancy is
  `1 − MemAvailable/MemTotal`; document that MemFree's real hazard is a permanently
  **alarming** tile on a warm page cache (the first draft had this inverted). And
  record honestly that Linux load average counts uninterruptible-sleep tasks, so a
  tile labelled CPU should use `/proc/stat` deltas if a true busy-% is wanted.
- Use `CLOCK_BOOTTIME` (not `CLOCK_MONOTONIC`) wherever elapsed time must survive
  suspend.
- **Acceptance**: parser tests over captured `/proc` fixtures; `throughput` and the
  history ring untouched and still green.

### JP-16 · Jetty · `NowPlayingProviding` — MPRIS2
**Branch** `claude/jp-16-mpris` · **Size** M

- Watch `org.mpris.MediaPlayer2.*` via `NameOwnerChanged`, proxy
  `/org/mpris/MediaPlayer2`, read `PlaybackStatus` + `Metadata`, subscribe
  `PropertiesChanged`. `xesam:artist` is an **array**.
- Split out a pure `MPRISPlayerSelector.pick(from:)` and `parse(metadata:)` so both
  join the tested backbone.
- **Correction**: do not present MPRIS as "strictly better" — it is opt-in per
  player, so a non-implementing player is invisible, and it *adds* a multi-player
  selection problem MediaRemote never had. Evaluate delegating selection to
  `playerctld`'s `ActivePlayer` (real last-activity ordering) instead of excluding
  that bus name.
- macOS keeps `MediaRemote/` behind `#if canImport(AppKit)`; nothing is deleted.
- Free bonus to wire up: `PlayPause`/`Next`/`Previous`, and a `DesktopEntry` key
  that feeds straight into PictKit's icon ladder.
- **Acceptance**: selector and parser unit tests; integration test against a mock
  MPRIS service under `dbus-run-session`.

### JP-17 · Jetty · `SleepWakeObserving` + the Pomodoro sound seam
**Branch** `claude/jp-17-sleep-wake` · **Size** S-M

- logind `PrepareForSleep(b)` on the system bus replaces the two `NSWorkspace`
  notifications. **Correction**: it is not an exact equivalent —
  `PrepareForSleep(true)` is a *pre*-sleep inhibitor-gated signal, not
  `willSleep`-then-`didWake`; document the difference where the Pomodoro timer reads it.
- `NSSound(named: "Glass")` → GSound playing the freedesktop `complete` event.
- These are the only two AppKit touches in `PomodoroTimer.swift`; removing them makes
  all 201 lines portable.
- **Acceptance**: `PomodoroTests` green on Linux.

---

## Part 5 — `jettyd`, the Linux daemon

### JP-18 · Jetty · Daemon skeleton + D-Bus + systemd unit
**Branch** `claude/jp-18-daemon-skeleton` · **Size** M

- Add `linux/Package.swift` (swift-tools 5.9) path-depending on the root package and
  PictKit, with executable `jettyd` and a `JettyDaemon` library target so tests can
  `@testable import` it. Copy Top Drawer's manifest shape and its `dbus` pin
  (`wendylabsinc/dbus`, `.upToNextMinor(from: "0.4.1")`).
- Own `ch.lkmc.Jetty` on the session bus, export `/ch/lkmc/Jetty` implementing
  `ch.lkmc.Jetty1`; introspection-XML-first so the frontend and the GJS extension
  can both codegen. Claim the name by calling `org.freedesktop.DBus.RequestName`
  yourself — the library has no helper.
- `linux/systemd/jettyd.service` (user unit), and the Linux CI job builds it.
- **Decide the run-loop story here, once, for both executables.** Nothing in a
  GLib main loop drains `DispatchQueue.main` or `RunLoop.main`, so Jetty's four
  `RunLoop.main.add(_:forMode: .common)` timers (`LiveSystemStats:76`,
  `PomodoroTimer:90`, `WindowPeek:36`, `UpdateChecker:99`) and its ~28
  `DispatchQueue.main` hops — including `NowPlayingService:42`'s watchdog, whose
  non-firing wedges the tile permanently — never run. If the bridge is a `GSource`
  on libdispatch's main-queue eventfd, it **must `eventfd_read()`** the descriptor:
  libdispatch pokes it with `eventfd_write` and never clears it, so a GSource that
  only polls spins the app at 100% CPU.
- **Acceptance**: `busctl --user introspect ch.lkmc.Jetty /ch/lkmc/Jetty` shows the
  interface; service tests under `dbus-run-session`.

### JP-19 · Jetty · Trash over the XDG spec + the inotify watcher
**Branch** `claude/jp-19-trash` · **Size** M

- Discover trash dirs from `/proc/self/mountinfo` plus the spec's two per-volume
  forms; count with one `readdir` of each `files/`; trash via `gio trash <path>`;
  empty by deleting `files/` + `info/` contents; open via
  `org.freedesktop.FileManager1.ShowFolders(["trash:///"])`.
- Copy PictKit's inotify pattern into `linux/` (whole-file Linux-only), with **one
  inotify instance and a `[wd: path]` map** rather than one instance per path
  (`max_user_instances` is 128). Say in the PR body why this is a deliberate copy
  rather than a reuse of `IconStoreWatcher`.
- **Delete on the Linux side**: `TrashStateResolver`, `FinderAutomation`, the
  AppleScript trash path and the Permissions-pane Finder-Automation row have no
  analogue — TCC does not exist. Keep `TrashLocations`' shape; change only the path
  formulas.
- Icon names are spec'd: `user-trash` / `user-trash-full`.
- **Acceptance**: `TrashIconTests` green; new tests over a fixture trash tree
  including a per-volume `.Trash-$uid`.

### JP-20 · Jetty · App model — index, launch, running state
**Branch** `claude/jp-20-app-model` · **Size** L (split if it grows past ~600 lines)

- Consume PictKit's `DesktopEntryIndex` (JP-12) for the dock's app items and the
  command bar.
- Launch via `systemd-run --user --quiet --scope --slice=app.slice
  --unit=app-jetty-<escaped-id>-<random>.scope` with the argv from the parsed `Exec`.
  **Pass `--expand-environment=no`.** `systemd-run` defaults
  `arg_expand_environment = true` and runs `replace_env_argv()` on the command line
  immediately before `execvpe`, so a desktop `Exec=` containing a literal `$` is
  silently rewritten. This is a correctness bug, not a nicety — add a test with a
  `$`-bearing `Exec` fixture. Also budget for unit-name length: systemd caps names at
  255 bytes and the gnome-desktop escape expands every non-`[A-Za-z0-9:_.]` byte to
  four characters, which a long Flatpak instance ID can overrun.
  `gio launch` only for `Terminal=true`; `gio open` for file/folder/URL tiles.
- Define `AppShell` with `runningApps`, `windows(of:)`, `activate`, `minimize`,
  `close` — **plus `hide`, `quit` and `forceQuit`**, which Jetty already ships
  (`Apps/AppLauncher.swift`, with `Apps/AppResponsivenessMonitor.swift` behind the
  force-quit affordance) and which the first draft of this item dropped.
- Implement the **degraded "no shell"** backend first so Jetty is installable on
  stock GNOME before the extension exists, with peek and minimise honestly greyed
  out. Two mechanisms the research missed, both better than the systemd-scope
  heuristic alone and both permission-free:
  - `org.freedesktop.DBus.ListNames` + `NameOwnerChanged`. Every `GApplication` with
    an application ID and default flags exports `org.freedesktop.Application`, so
    this is an *exact* running signal for a large share of the app set, and it also
    gives `Activate`/`Open`/`ActivateAction` for launching.
  - gnome-shell's introspection **signals** (`RunningApplicationsChanged`,
    `WindowsChanged`) are emitted with **no** sender check, even though its getters
    are allowlisted to the two portal backends. So a stock-GNOME backend can be
    notified of changes for free, and only the *read* needs another route.
  Keep systemd scopes as the third source (exact for anything Jetty itself launched).
  Then wlr-foreign-toplevel and plasma-window-management.
- **Activation will fail for reasons that are not API availability.** Mutter's
  `meta_window_activate_full` drops activation requests that fail focus-stealing
  prevention — and Jetty is precisely the app that must not take focus itself. Treat
  "the call succeeded but the window did not raise" as the expected first result and
  design the timestamp/startup-notification handling for it.
- **Acceptance**: index and launch unit tests; `AppShell` conformance tests per
  backend; the degraded backend proven against a real `systemd-run` scope in CI.

### JP-21 · Jetty · Folder stacks + thumbnails
**Branch** `claude/jp-21-stacks` · **Size** M

- Directory read behind the JP-11 pure sort/cap; entry icons via shared-mime-info
  (`globs2`, `generic-icons`, `aliases`) into the icon-theme lookup from JP-13;
  thumbnails read (not generated) from the freedesktop cache at
  `~/.cache/thumbnails` — MD5 of the URI, so take `Crypto.Insecure.MD5` behind the
  standard `#if canImport(CryptoKit)` idiom.
- Reveal-in-file-manager via `org.freedesktop.FileManager1.ShowItems`.
- **Acceptance**: MIME→icon-name resolution tests; thumbnail-cache path tests.

### JP-22 · Jetty · Hotkeys + power commands
**Branch** `claude/jp-22-hotkeys-power` · **Size** M

- `HotkeyBinder` with four implementations selected by **probing, never by desktop
  name**: extension keybinding, GlobalShortcuts portal, compositor config + a
  `jetty-cli` verb, GSettings custom-keybindings (documented, never auto-written).
  On 24.04 the expected portal error is `UnknownMethod`. Render the portal's returned
  `trigger_description` rather than Jetty's own `displayString`.
- `LinuxHotkeyTranslator`: invert `HotkeyBinding.label(for:)`'s closed glyph set into
  keysym names, map Carbon modifier bits to `CTRL/ALT/SHIFT/LOGO`, and mark anything
  unmappable as needing re-record.
- `PowerCommand.linuxAction` as a pure value beside `appleScript`; four of six go to
  `org.freedesktop.login1.Manager` with its `Can*` probes driving greyed-out items.
  Lock Screen uses `login1.Session.Lock()` — **never**
  `org.freedesktop.ScreenSaver.Lock()`, a declared-but-unimplemented stub on GNOME.
  Only Log Out branches per desktop, resolved by asking the bus who owns
  `org.gnome.SessionManager` / `org.kde.Shutdown`.
- **Acceptance**: translator unit tests; portal client tested against a mock service;
  `PowerCommandTests` extended with the Linux action table.

### JP-23 · Jetty · Tray, autostart, single-instance
**Branch** `claude/jp-23-tray-lifecycle` · **Size** M

- StatusNotifierItem + `com.canonical.dbusmenu`, hand-rolled over the Swift D-Bus
  library (GTK4 removed `GtkStatusIcon`; the ayatana packages are rejected — GTK3-only
  or exporting a menu interface Ubuntu's extension does not implement).
- Launch at login: an XDG autostart `.desktop` in `~/.config/autostart/`, written at
  runtime by the toggle, not shipped by the package.
- Single-instance via D-Bus name ownership (replacing the `NSRunningApplication`
  guard), and a clean shutdown that restores whatever JP-33 stood down.
- **Acceptance**: SNI registers and shows a menu on a real GNOME/KDE session
  (manual, documented); name-ownership tests under `dbus-run-session`.

---

## Part 6 — `jetty-shell`, the layer-shell frontend

*C interop starts here. Copy Top Drawer's `CGtk4` / `CGtkLayerShell` targets and its
CI action that builds gtk4-layer-shell from source on noble.*

### JP-24 · Jetty · GTK4 + layer-shell "hello dock"
**Branch** `claude/jp-24-layer-shell-hello` · **Size** M

- One anchored, undecorated window per display: `gtk_layer_init_for_window` **before
  realize**, `set_layer(OVERLAY)`, `set_anchor`, `set_margin`,
  `set_exclusive_zone(0)`, `set_keyboard_mode(NONE)`, `set_monitor`, namespace
  `"jetty"`. Reads dock data from `jettyd`; logs pointer enter/leave and clicks.
- **The single deliberate y-flip lives here**, in a new unit-tested
  `LinuxScreenSpace.swift`: feed `DockLayout` a per-output local y-up
  `CGRect(0, 0, usable.width, usable.height)` and convert its output to
  `marginTop = usableH − frame.maxY`. A second, panel-local flip feeds
  `pointerOverDockContent`. **Two flip sites, no more.**
- Assert `gtk_layer_is_supported()` at startup and fail with a clear message; ship
  the launcher with `LD_PRELOAD` set, because gtk4-layer-shell is a
  symbol-interposition shim that does nothing if libwayland loads first. (It does
  warn — the failure is loud, not silent.)
- **Acceptance**: builds in CI (no compositor there); `LinuxScreenSpace` tests green;
  manual verification on KDE/Sway documented honestly in the PR.
- **Pitfalls**: `set_exclusive_zone(0)` is right (never `-1`, which would put Jetty
  under other panels; never positive, which would reserve space and break the app's
  one load-bearing design decision). There is **no readback** of the resulting usable
  area — use a throwaway four-edge-anchored probe surface when a number is genuinely
  needed. Centre-plus-offset placement cannot be expressed by anchors alone.

### JP-25 · Jetty · Tile rendering + magnification
**Branch** `claude/jp-25-tiles` · **Size** L

- A `GtkFixed` holding one tile widget each; icons as `GdkTexture` built once from
  PictKit's `ResolvedIconImage` via `gdk_memory_texture_new` (check the
  premultiplied/byte-order match against `CAIRO_FORMAT_ARGB32` and add a round-trip
  test); labels through PangoCairo for synchronous measurement.
- Magnification and the reveal slide are driven by `gtk_widget_add_tick_callback` —
  **never** window geometry, **never** `gtk_layer_set_margin` per frame.
- **Correction, and it decides the widget tree**: `gtk_fixed_set_child_transform` is
  *not* the `CALayer`-transform analogue the research assumed. GSK re-rasterises the
  transformed subtree at the new effective scale, so transforming a cairo-drawn
  `GtkDrawingArea` re-runs its draw function every frame of a magnification sweep —
  the exact cost the macOS design avoids. **Rasterise each tile once into a
  `GdkTexture` and scale the texture**; do not put a `GtkDrawingArea` under a
  per-frame transform. Two related hazards: `GtkFixed` neither grows nor
  clip-extends for a scaled child (so a magnified tile clips at the container's
  allocation unless the layout reserves JP-07's headroom), and `GskTransform` is
  transfer-full with no ARC in Swift (`gsk_transform_translate` *consumes* its first
  argument and returns a new reference, imported as an `OpaquePointer` with no
  compiler help).
- Size icons in **device** pixels against `gdk_surface_get_scale()`, which is a
  `double` since GTK 4.12 — fractional scaling is not an integer factor.
- **Acceptance**: view-model tests populating a strip from document fixtures; builds
  in CI; a frame-time measurement over a full magnification sweep recorded in the PR
  from a real session, which is the number that proves the texture decision.

### JP-26 · Jetty · Reveal, auto-hide, and the sliver
**Branch** `claude/jp-26-reveal` · **Size** M

- A second 1–2 px layer surface per display; its `GtkEventControllerMotion` enter
  event is the reveal trigger, consuming JP-07's `DockRevealPolicy` unchanged.
- **Correction, load-bearing**: put the sliver on **`OVERLAY`, not `TOP`** — on both
  KWin and sway the TOP layer sits *below* an active fullscreen window, which would
  silently kill reveal exactly where Jetty advertises it. Since ordering *within* a
  layer is undefined, unmap the sliver while revealed rather than relying on z-order.
- Click-through while hidden via `gdk_surface_set_input_region` (gated by
  `gdk_display_supports_input_shapes()`, and only after the `GdkSurface` exists);
  fall back to unmapping, which is preferable anyway — a permanently mapped
  transparent overlay over a fullscreen game defeats direct scanout.
- **Retire `hideDistance` on Linux** and say so in the release notes: a client sees
  pointer events only over its own surfaces. Do not fake it by inflating the input
  region.
- **Spike first**: KWin implements `installAutoHideScreenEdgeV1()` — a
  compositor-side auto-hide-and-reveal for layer surfaces, directly relevant to
  Jetty's central behaviour. Evaluate it before hand-rolling the sliver on KDE.
- **Acceptance**: policy tests reused unchanged; manual reveal verification on KDE
  and Sway, including over a fullscreen window.

### JP-27 · Jetty · Drag & drop
**Branch** `claude/jp-27-dnd` · **Size** M

- `GtkDropTarget` on the dock and the sliver accepting `GdkFileList` / `text/uri-list`
  with **actions COPY|MOVE** — Nautilus rejects COPY-only drops wholesale.
- Drop on the sliver reveals then pins (the `DragRevealSensorView` analogue); drop on
  a folder tile moves; drop on Trash calls `gio trash`; reorder within the strip
  reuses JP-06's `DockDragPolicy`.
- **Acceptance**: target-resolution tests reusing the pure drag policy; a real
  Nautilus drop verified manually and recorded.

### JP-28 · Jetty · Popovers: folder stacks, context menus, the Jetty Menu
**Branch** `claude/jp-28-popovers` · **Size** L

- **Spike this first, before the rest of the item.** All three of these features
  become `xdg_popup`s parented to a *layer* surface, which needs layer-shell v2's
  `get_popup` and is unverified on our target compositors. If `GtkPopover` on a layer
  surface does not work, stacks/menus/peek all need separate layer surfaces
  positioned by hand — a different design, and better to learn that here than in
  JP-29.
- Folder-stack popover and tile context menus positioned by JP-11's
  `FolderStack.origin` and JP-06's `DockContextMenuPlacement`.
- **The Jetty Menu gets its own layer surface at `ON_DEMAND`**, leaving the dock at
  `NONE` — this is how the macOS "briefly activate, hand back on close" exception
  translates, and it avoids the popup keyboard-mode inheritance rule entirely.
- Rewire the dwell gate from `NSMenu` presentation to `GtkPopover::closed`, which is
  asynchronous where the AppKit path was synchronous.
- **Acceptance**: placement tests green unchanged; type-to-find works in the menu on
  a real session.

### JP-29 · Jetty · Widget tiles on GTK
**Branch** `claude/jp-29-widget-tiles` · **Size** L

- Render the clock faces (analog, LCD, seven-segment), battery, weather, world
  clock, Pomodoro, system monitor and now-playing tiles in cairo over the JP-10
  cores and the JP-14…JP-17 providers.
- **Acceptance**: golden-image tests for the deterministic faces (the seven-segment
  and LCD renders are pure functions of the formatter output); builds in CI.

### JP-30 · Jetty · Linux settings surface
**Branch** `claude/jp-30-settings` · **Size** L

- A GTK4 (optionally libadwaita) settings window over `PreferencesModel`, covering
  General / Appearance / Items / Displays / Widgets / Menu / About. Hotkey recording
  goes through the JP-22 binder, showing the portal's own description where that tier
  is in use.
- **Acceptance**: preference round-trip tests; manual pass over every pane.

---

## Part 7 — The GNOME Shell extension (stock Ubuntu)

### JP-31 · Jetty · Extension skeleton + window management
**Branch** `claude/jp-31-extension-skeleton` · **Size** L

- A thin GJS extension that positions Jetty's *real* windows (`move_resize_frame`,
  `unmake_above()` **before** `make_above()`, `stick()`) — a **normal** window type,
  never DOCK, which Mutter demotes under fullscreen. Match windows by
  `gtk_application_id` (arrives asynchronously on Wayland) or own them via
  `Meta.WaylandClient`.
- All logic stays in `jettyd`; the extension speaks the JP-18 D-Bus interface.
- **Acceptance**: `gnome-extensions pack/install/enable`; a nested session
  (`--devkit` on GNOME 49+, `--nested` on ≤48) shows a positioned, above dock.

### JP-32 · Jetty · Extension: reveal, hotkeys, running apps
**Branch** `claude/jp-32-extension-input` · **Size** M-L

- `Meta.Barrier` pressure barriers for edge reveal (note the constructor changed from
  `display:` to `backend:` — version-gate it); `Main.wm.addKeybinding` for hotkeys
  with no dialogs; `Shell.AppSystem`/`WindowTracker` for the exact running-apps and
  window feed, proxied over the same interface.
- **Trap to engineer around**: barriers are motion-triggered, so unlike a layer-shell
  sliver's map-time enter event they will *not* fire after a hotplug or a settings
  change — the dock can stay hidden until the pointer moves. Seed the state
  explicitly (the macOS code does the same thing at `DockController.swift:377-381`).
- Focus must be managed explicitly here; layer-shell gives it away for free.
- **Acceptance**: barrier reveal, both hotkeys, and running dots verified in a nested
  session and recorded.

### JP-33 · Jetty · Standing down the desktop's own panel + first run
**Branch** `claude/jp-33-system-panel` · **Size** M

- Re-implement the **Restore System Dock** promise per tier: on Ubuntu GNOME,
  `gnome-extensions disable ubuntu-dock@ubuntu.com` (per-user GSettings, reversible);
  on KDE, the Plasma panel setting; on wlroots, usually nothing to do. Keep
  `SystemDockController`'s *policy* — capture prior state, apply, re-assert, restore
  faithfully, never clobber settings we did not set — which is pure and ports; only
  the backend swaps.
- First-run flow: a `.deb`-shipped extension is **not discovered until the next login
  and is never auto-enabled**, so deep-link the Extensions app and keep the daemon
  useful meanwhile (tray + portal hotkeys).
- **Acceptance**: enable/disable round-trip leaves the user's own settings exactly as
  found, proven by a test over a fake GSettings backend.

---

## Part 8 — Packaging and updates

### JP-34 · Jetty · Debian packaging
**Branch** `claude/jp-34-deb` · **Size** M

- Copy Top Drawer's `build-deb.sh`. Static-link the Swift runtime
  (`--static-swift-stdlib`); do **not** bundle `.so`s and do **not** depend on
  Ubuntu's `swiftlang`. Ship the binaries, `/usr/share/applications/<app-id>.desktop`
  (`NoDisplay=true`), icons, the systemd user unit, and the extension zip under
  `/usr/share/jetty/`. `lintian --fail-on error`.
- Dependencies resolve via `dpkg-shlibdeps`; add `libglib2.0-bin`,
  `dbus-user-session`, `hicolor-icon-theme`, `adwaita-icon-theme`,
  `shared-mime-info`, `desktop-file-utils`; `upower`, `xdg-desktop-portal-gnome |
  xdg-desktop-portal-kde` and `xdg-utils` as Recommends; a file manager as Suggests.
- **Acceptance**: the `.deb` installs and the dock runs on a clean Ubuntu 26.04 VM;
  built and lintian-clean in CI; attached to releases.

### JP-35 · Jetty · Linux update flow + documentation
**Branch** `claude/jp-35-updates-docs` · **Size** M

- The existing `UpdateChecker`/`UpdateDownloader` port with a `.deb`/`.AppImage`
  asset preference. Keep the `.bak` rotation, corrupt-quarantine and
  newer-version-refusal semantics exactly — they are tested and load-bearing.
- Update `README.md`, `AGENTS.md` (a Linux section mirroring the macOS one) and
  `PLAN.md`; document the tier matrix honestly, including that stock GNOME needs the
  extension and that `hideDistance` is macOS-only.
- **Acceptance**: an end-to-end update on a real install; docs reviewed against the
  shipped behaviour.

---

## Done means done

The port is complete when: Jetty's Linux CI is green on `main`; `JettyCore` builds and
its ~95%-portable test suite runs on both platforms; `jettyd` + `jetty-shell` deliver
an auto-hiding, magnifying, non-reserving dock with launch, running state, DnD,
hotkeys, stacks, trash and the info tiles on a layer-shell compositor; the GNOME Shell
extension delivers the same on stock Ubuntu; and the `.deb` builds in CI. Follow-ups
collected along the way (AppImage, an apt repo, window peek's live previews,
SwiftCrossUI for the settings pane) live as issues, not as scope.
