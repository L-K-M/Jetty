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
- **File-system-synchronized Xcode groups are a trap here.** `Jetty` and `JettyTests`
  are `PBXFileSystemSynchronizedRootGroup`s, so any new `.swift` file under `Jetty/`
  is automatically added to the macOS target. Keep Linux-only code in `linux/`,
  outside `Jetty/`, and give the rare file that must live under `Jetty/` a whole-file
  `#if os(Linux)`. (Strictly, synchronized groups *do* support per-target membership
  exceptions — `PBXFileSystemSynchronizedBuildFileExceptionSet` — so this is a
  convention rather than a hard constraint; prefer the guard anyway, since it is
  visible in the file rather than in project state.)
- **Never run bare `xcodebuild`** in this repo — always pass `-project`, so the root
  `Package.swift` and `Jetty.xcodeproj` coexist safely. `ci.yml` and
  `scripts/build.sh` already do; confirm the shared `lkm-build` engine does too.
- **Extraction PRs are pure moves.** No behaviour change, no reformatting; the
  existing tests move with the code and must pass unchanged on both platforms.
- **`JettyCore` is a subset, not a second target.** The SwiftPM library target is
  named **`Jetty`** at `path: "Jetty"`, and it has to be: the existing test files say
  `@testable import Jetty`, and they are compiled by *both* the Xcode test target
  (where the module is the app) and the SwiftPM one, so any other module name means
  guarded imports in test files. `JettyCore` is this document's name for the
  **portable subset** of that module — the curated `sources:` list JP-01 seeds.
  So "move X into `JettyCore`" in Part 2 means *add X to that list* (splitting the
  file first where only half of it is portable), never "create a `JettyCore` target"
  and never "relocate the file on disk". Nothing here needs a second Xcode target or
  a `project.pbxproj` edit: the file-system-synchronized group keeps compiling the
  same files into the app either way.

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

### JP-01 · Jetty · Root `Package.swift` + the `JettyCore` subset + Linux CI
**Branch** `claude/jp-01-linux-ci` · **Size** M · **Why**: `linux-port.md` §Build

- Add a root `Package.swift` (swift-tools 5.9): library target **named `Jetty`** at
  `path: "Jetty"` and test target **`JettyTests`** at `path: "JettyTests"`, each with
  a curated `sources:` list, so the existing `@testable import Jetty` files compile
  unmodified.
- **Both targets need an `exclude:` list, not just the library one** — the gate below
  is per-target, and a test target with 24 unlisted files fails it just as loudly.
  Built and measured against the tree as it stands: **57 entries** on `Jetty`
  (`Resources`, `MediaRemote`, `Jetty.entitlements`, `AppDelegate.swift`,
  `JettyApp.swift`, the ten wholly-macOS directories — `Apps`, `Common`, `Hotkeys`,
  `Icons`, `Settings`, `Stacks`, `Store`, `SystemDock`, `Windows` — and 43 individual
  files in the six directories the curated set only half-claims: `Dock` 10, `Menu` 9,
  `Model` 5, `Screens` 1, `Updates` 1, `Widgets` 17), and **24 entries** on
  `JettyTests`. Know the ongoing cost before signing up for it: a new macOS file in
  one of those six mixed directories now fails Linux CI until it is either ported or
  excluded. That is the gate doing its job — the decision is forced rather than
  skipped — but it is a decision on *every* new file there, and the list only shrinks
  as Part 2 moves things into the curated set.
- Seed `sources:` with this exact set of **24 files**. It is not a guess: it was
  built and its tests run on Swift 6.3.3 / Ubuntu 24.04 while this plan was being
  written — **116 tests across 9 suites, 0 failures**.

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
  - **Delete** `import SwiftUI` from `DecorationPosition` outright: its only
    SwiftUI-looking need is `Identifiable`, which has been standard library since
    Swift 5.1, and the file type-checks on Linux with no import at all (verified).
    `DecorationStyle` keeps the import but guarded, `#if canImport(SwiftUI)`,
    **plus** a `#if canImport(SwiftUI)` around
    `DecorationStyle.colors` alone (`DecorationStyle.swift:45-47`), which maps the
    pure `hexes` array through SwiftUI's `Color`. `hexes` itself stays portable.
  - `#if canImport(AppKit)` around **`DockItem`'s three classifier factories**
    (`DockItem.swift:61-89`) **and** its `import AppKit` line (there is no AppKit
    module on Linux, so that import must be guarded like the others). The *API*
    blocker is not the import but `fromFileURL`'s `TrashLocations.isTrashURL` call. The Codable half — which is
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
- **Pitfalls**: don't reformat while adding guards. Do **not** add
  `Model/Preferences.swift` or `Model/ColorHex.swift` yet (they are `ObservableObject`
  / `NSColor` — JP-02 and JP-04).
- **A curated `sources:` list does not silently ignore the rest.** The corpus's Part 10
  pin says unlisted files are ignored without warning; on Swift 6.3.3 that is wrong,
  and I reproduced it here — the build prints
  `warning: 'jetty': found 87 file(s) which are unhandled` and then names every one.
  That is louder than expected but still not a gate, and the consequence the pin
  warns about stands: an unlisted file is not compiled or tested on Linux, so a pure
  file added later on the macOS side goes unnoticed. The cheap mitigation follows
  from the real mechanism: `exclude:` the macOS-only files and directories until the
  unhandled list is **empty**, then gate Linux CI on the build log itself —
  `swift build 2>&1 | tee build.log && ! grep -q 'which are unhandled' build.log` —
  so the next unlisted file fails instead of being scrolled past. Do **not** reach
  for `-Xswiftc -warnings-as-errors` here, which an earlier draft of this plan
  suggested: that warning is emitted by SwiftPM during target planning, never by the
  compiler, so `-Xswiftc` cannot promote it. Verified — a package with one unlisted
  file builds and exits 0 under `-Xswiftc -warnings-as-errors` while printing
  `found 1 file(s) which are unhandled`. No separate file-diff check is needed.
  The whole arrangement — both `exclude:` lists, the corrected guards, an empty
  unhandled list and 116 green tests — was assembled and run before this plan
  merged, so JP-01 is transcription, not discovery.

### JP-02 · Jetty · Combine compatibility shim
**Branch** `claude/jp-02-observation-compat` · **Size** S

- Copy Top Drawer's merged `ObservationCompat.swift` into `Jetty/Common/`, guarded
  so it is Linux-only and additive; macOS keeps real Combine.
- Bring `Model/Preferences.swift`, `Widgets/WeatherService.swift` and the other
  `ObservableObject` types that are otherwise portable into the `sources:` list.
- **Decline the full `@Observable` migration** and record why in the PR body:
  Jetty has 96 `@Published` / 15 `ObservableObject` but only **6** `.sink` chains
  (in `DockController`, `JettyMenuModel` and `PomodoroTimer`, plus
  `PermissionsView`'s `Timer.publish`); converting 15 types is a large macOS-visible
  diff for zero Linux benefit.
- **Two shim gaps to check before relying on it**, from the adversarial pass:
  `AnyCancellable` is not `Hashable` under the shim, so `Set<AnyCancellable>` — the
  canonical bag, and what `DockController` uses — will not compile; and
  `ObservableObject` conformance details differ. Both are in files that stay
  macOS-only at this stage, so they do not block JP-02; fix them when JP-08 moves
  `DockController`'s policies, and say so in the PR body rather than discovering it
  there.
- **Acceptance**: `Preferences` and `WeatherService` compile and test on Linux;
  macOS diff is additive only.

---

## Part 2 — Core extraction (macOS-improving; validated by macOS CI)

*Each item is a **pure move** into `JettyCore` with its tests — a `sources:`
addition, not a new target; see Part 0. Land them in order; each is small enough to
review as a move.*

### JP-03 · Jetty · Geometry core: `DockLayout` + `MagnificationCurve`
**Branch** `claude/jp-03-geometry-core` · **Size** S-M

- Move all 362 LOC of `DockLayout` and `MagnificationCurve` with `DockEdge`,
  `DockAlignment`, `DockAnchor`. They already have zero platform API.
- Add a **new pure** `DockLayout.layerShellPlacement(frame:in:edge:)` →
  `(anchorEdges, margins, exclusiveZone)`, unit-tested against the existing
  `DockLayoutTests` fixture (`CGRect(0, 0, 1000, 800)` — already per-output local
  space, so every existing assertion stays valid verbatim).
- `DockLayout` carries **six** "keep in sync" markers (lines 59, 80, 108, 119, 293,
  306): `DockTileView.tileWidth`, the LCD's `caseH * 1.35`, `ClockWidgetView`'s edge
  padding, the hover-capsule ~16pt, `DockView.scale`'s 2.2 influence factor, and
  `clockZoomHeadroom`. Make each a named `JettyCore` constant rather than a literal
  duplicated across files with a comment asking the next reader to keep them aligned.
- **Acceptance**: `DockLayoutTests`, `DockLayoutGapTests`, `MagnificationCurveTests`
  green on both platforms, unchanged.
- **Pitfalls**: `DockLayout` is Cocoa bottom-left-origin y-up throughout. Do **not**
  flip it here. The single deliberate flip belongs at the toolkit boundary (JP-24).

### JP-04 · Jetty · Document + store core
**Branch** `claude/jp-04-document-core` · **Size** M

- Move `DockDocument` + the `Failable<T>` lenient-decode wrapper, `DockItem`'s
  Codable half + `dedupKey` (separated from its three classifier factories).
  `clampOffset`/`clampInset` are **not** listed here: they are static members of
  `DockAnchor` in `Model/DockAnchor.swift`, which JP-03 already moves whole.
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
  `/var/lib/snapd/desktop/applications` and both Flatpak export dirs
  (`~/.local/share/flatpak/exports/share/applications`,
  `/var/lib/flatpak/exports/share/applications`) — never
  trust `$XDG_DATA_DIRS` alone. Apply the XDG defaults (`$XDG_DATA_HOME` →
  `~/.local/share`, `$XDG_DATA_DIRS` → `/usr/local/share:/usr/share`) and pin the
  precedence order — `$XDG_DATA_HOME`, then `$XDG_DATA_DIRS` left to right, then
  Flatpak user and system exports, then snapd — because "first-wins" is meaningless
  without it, and scanning system dirs first lets a system entry shadow a user's
  override.
- **Derive the desktop-file ID per the menu spec**: the path relative to the
  applications directory with `/` replaced by `-`, so
  `applications/kde4/konsole.desktop` is `kde4-konsole.desktop` and does *not*
  collide with `applications/konsole.desktop`. A basename implementation silently
  merges them — and since this index also replaces `DesktopOverrideSync`'s ID guess,
  a different derivation would stop existing override files matching.
- Give each filtering key defined semantics rather than "honour": `Hidden=true` →
  drop the entry — but **after** desktop-file-ID resolution, not at parse time. The
  spec's "treat as if it did not exist" is what makes a `Hidden=true` file in
  `$XDG_DATA_HOME/applications` the standard way to *uninstall* a vendor entry of the
  same ID from `/usr/share/applications`: the Hidden entry has to win first-wins and
  take the ID out of the index with it. Drop it while scanning and the system twin
  re-surfaces;
  `NoDisplay=true` → index it but exclude it from search and default listings;
  `OnlyShowIn`/`NotShowIn` matched case-sensitively against the colon-separated
  `$XDG_CURRENT_DESKTOP`, with unset meaning `OnlyShowIn` entries lose; `TryExec`
  resolved at index time against the **user session's** `$PATH`, not the indexing
  process's — a daemon or systemd user service can have a minimal `PATH` in which
  `~/.local/bin` entries look uninstalled and vanish from the dock — and re-evaluated
  on every reindex. Three apps consume this, so an
  under-specified "honour" is exactly the drift the shared index exists to prevent.
  Resolve `Name`/`GenericName`/`Keywords` by the spec's locale ladder.
- Parse `Exec` per spec: quoting rules and field codes (`%f %F %u %U %i %c %k`),
  returning an argv array; strip the deprecated codes (`%d %D %n %N %v %m`) and
  unescape `%%` to a literal `%`. Remember `%i` expands to **two** argv entries
  (`--icon` and the value) — or **zero** when `Icon` is empty or absent, which is the
  fixture that catches a naive implementation emitting `--icon ""` — and `%c` is the
  *localised* name. **Never** build a shell
  string.
- Retire `DesktopOverrideSync.overrideFilename(forSystemPath:)`'s documented
  best-effort desktop-ID guess in favour of the real index.
- **Acceptance**: unit tests over hostile fixtures (quoting, embedded `%`, `%i` with
  no `Icon` key, missing `Exec`, bad locale keys, symlink loops, and a `Hidden=true`
  user entry masking a same-ID system one) before anything is ever executed; existing
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
  `isLowBattery(percent:isPlugged:)`. Derive `isPlugged` from `State` instead:
  cover the whole enum (0 Unknown / 1 Charging / 2 Discharging / 3 Empty /
  4 FullyCharged / 5 PendingCharge / 6 PendingDischarge), because the pending states
  are what a ThinkPad or ASUS charge threshold parks the battery in and both mean
  line power is connected: `Discharging` ⇒ unplugged,
  `Charging`/`FullyCharged`/`PendingCharge`/`PendingDischarge` ⇒ plugged,
  `Empty`/`Unknown`/anything unrecognised ⇒ hold the last known value.
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
  Linux, and make it **type-aware rather than prefix-only**: drop interfaces whose
  `/sys/class/net/<if>/type` is `ARPHRD_LOOPBACK` (772) or `ARPHRD_NONE` (65534),
  then apply a prefix list for the `ARPHRD_ETHER` virtuals a type check cannot catch
  (`docker*`, `veth*`, `br-*`, `virbr*`, `ovs*`, `tun*`, `tap*`, `wg*`, `ppp*`,
  `zt*`, `tailscale*`, `sit*`, `ip6tnl*`, `ip_vti*`). A prefix-only list both rots as
  new tools ship and misses the tunnel scaffolding (`sit0`, `ip6tnl0`, `gre0`) that
  is present by default on many distros.
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
- **`NameOwnerChanged` reports only transitions**, so install the match rule
  (`arg0namespace='org.mpris.MediaPlayer2'`) **first**, then take an
  `org.freedesktop.DBus.ListNames` snapshot and dedupe arrivals against it. Without
  the snapshot every player started before the dock — the common case, since the dock
  autostarts — is invisible, and an integration test whose mock service starts *after*
  the watcher would not catch it. So cover **both** orders under `dbus-run-session`:
  mock-before-watcher exercises the snapshot, watcher-before-mock exercises the live
  `NameOwnerChanged` arrival, and each must find the player on its own.
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
- **Acceptance**: selector and parser unit tests; integration tests against a mock
  MPRIS service under `dbus-run-session`, in both start orders.

### JP-17 · Jetty · `SleepWakeObserving` + the Pomodoro sound seam
**Branch** `claude/jp-17-sleep-wake` · **Size** S-M

- logind `PrepareForSleep(b)` on the system bus replaces the two `NSWorkspace`
  notifications. **Correction**: it is not an exact equivalent —
  `PrepareForSleep(true)` is a *pre*-sleep inhibitor-gated signal, not
  `willSleep`-then-`didWake`; document the difference where the Pomodoro timer reads
  it. A `delay` inhibitor must be taken **before** suspension begins — it cannot
  usefully be acquired inside the handler — and the handler must return promptly or
  it stalls the suspend.
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
  (`wendylabsinc/dbus`, `.upToNextMinor(from: "0.4.1")`). Add **`swift-crypto`**
  here too — JP-21 needs `Crypto.Insecure.MD5` for thumbnail-cache names and there
  is no CryptoKit on Linux.
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

- Discover trash dirs: **`$XDG_DATA_HOME/Trash` (default `~/.local/share/Trash`)**
  for the volume holding the home directory — the spec's primary can, and where most
  deletions land on a single-volume install — plus, for *other* mounts in
  `/proc/self/mountinfo`, the two per-volume forms (`$topdir/.Trash/$uid`, which
  requires the sticky bit and must not be a symlink, and `$topdir/.Trash-$uid`, which
  the spec requires to be an ordinary directory, not a symlink, owned by the user —
  check that before counting into it and especially before *emptying* it).
  Applying the per-volume forms to `/` instead would probe `/.Trash-$uid` and read
  empty right after the user trashed something. Count with one `readdir` of each
  `files/`; trash via `gio trash -- <path>` invoked with an **argv array, never a
  shell string** (the `--` stops a file named `-x` being parsed as an option);
  empty by deleting `files/` + `info/` contents; open via
  `org.freedesktop.FileManager1.ShowFolders(["trash:///"])`.
- Copy PictKit's inotify pattern into `linux/` (whole-file Linux-only), with **one
  inotify instance and a `[wd: path]` map** rather than one instance per path
  (`max_user_instances` is 128). Say in the PR body why this is a deliberate copy
  rather than a reuse of `IconStoreWatcher`. **Drop the `CInotify` import while
  copying**: the shim turns out to be unnecessary on Swift 6.3.3 — the adversarial
  pass compiled and ran `inotify_init1`/`inotify_add_watch`/`inotify_rm_watch` with
  `import Glibc` alone, and `MemoryLayout<inotify_event>.size` is 16 as expected. One
  fewer target in the graph.
- Trash counting is **one `readdir` scan of each `files/`, returning full at the
  first entry that is not `.` or `..`** — and it spans the per-volume cans, not just
  the home one. `TrashLocations.candidateTrashURLs()` deliberately covers both, and
  the freedesktop layout has two per-volume forms (`$topdir/.Trash/$uid` and
  `$topdir/.Trash-$uid`); a home-only implementation silently under-reports.
- **Icon gap to close in this item**: `user-trash-full` exists in Adwaita **only as
  SVG** (and `user-trash` only as a 16×16 PNG plus SVG). Adwaita is the fallback
  whenever Yaru is not active, i.e. on all non-Ubuntu GNOME. PictKit's Linux image
  path is swift-png — **PNG only, no SVG rasteriser** — so the Trash tile has no
  artwork on those systems unless Jetty either shells out to `rsvg-convert` (the
  JP-13 sandbox recipe) or ships its own PNGs. Decide here; it is not free.
- **Delete on the Linux side**: `TrashStateResolver`, `FinderAutomation`, the
  AppleScript trash path and the Permissions-pane Finder-Automation row have no
  analogue — TCC does not exist. Keep `TrashLocations`' shape; change only the path
  formulas.
- Icon names are spec'd: `user-trash` / `user-trash-full`.
- **Acceptance**: `TrashIconTests` green; new tests over a fixture trash tree
  including a per-volume `.Trash-$uid`, plus one that is a symlink and one owned by
  another uid, both of which must be skipped for counting and for emptying.

### JP-20 · Jetty · App model — index, launch, running state
**Branch** `claude/jp-20-app-model` · **Size** L (split if it grows past ~600 lines)

- Consume PictKit's `DesktopEntryIndex` (JP-12) for the dock's app items and the
  command bar.
- Launch via `systemd-run --user --quiet --scope --slice=app.slice
  --unit=app-jetty-<escaped-id>-<random>.scope` with the argv from JP-12's `Exec`
  parser — the spec grammar (quotes, backslash escapes, field codes), never
  whitespace splitting, and never a shell string. Honour `Path=` with
  `--working-directory=`.
  **Pass `--expand-environment=no`.** `systemd-run` defaults
  `arg_expand_environment = true` and runs `replace_env_argv()` on the command line
  immediately before `execvpe`, so a desktop `Exec=` containing a literal `$` is
  silently rewritten. This is a correctness bug, not a nicety — add a test with a
  `$`-bearing `Exec` fixture. Also budget for unit-name length: systemd caps names at
  255 bytes and the gnome-desktop escape expands every non-`[A-Za-z0-9:_.]` byte to
  four characters, which a long Flatpak instance ID can overrun.
  `gio launch` only for `Terminal=true`; `gio open` for file/folder/URL tiles.
  **`--scope` is load-bearing, not a style choice**, and a later reviewer will try to
  "fix" it: a transient *service* is spawned by the user manager and gets the
  manager's environment, so a session that never imported `WAYLAND_DISPLAY` /
  `DISPLAY` / `XAUTHORITY` into the manager launches apps that cannot reach the
  compositor. A transient *scope* is forked by `systemd-run` itself, which
  systemd-run(1) states "will thus inherit the execution environment of the caller" —
  i.e. `jettyd`'s, which is the session's. If this ever has to become a service, every
  one of those variables needs an explicit `--setenv=`.
  Also honour `DBusActivatable=true` per spec — `org.freedesktop.Application.Activate`
  on the bus name matching the desktop-file ID — before falling back to `Exec`, or
  single-instance apps get a second process instead of a hand-off.
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
  `$XDG_CACHE_HOME/thumbnails/{normal,large}/<md5>.png` — `normal` is ≤128px, `large`
  ≤256px, pick by requested size, and **never read `fail/`**, whose entries record
  failed generation rather than artwork. The name is the MD5 of the canonical
  percent-encoded absolute URI, so take `Crypto.Insecure.MD5` behind the standard
  `#if canImport(CryptoKit)` idiom — which means declaring **`swift-crypto`** in
  `linux/Package.swift` (JP-18), since CryptoKit does not ship with the Linux
  toolchain and the `#else` arm imports `Crypto` from that package. Treat a thumbnail as valid only when its
  `tEXt::Thumb::MTime` matches the file's current mtime, otherwise it is stale and
  must not be shown.
- **The URI must be escaped glib's way, not `URL.absoluteString`'s.** GIO hashes a
  canonical URI built with `g_escape_uri_string(…, UNSAFE_PATH)` — RFC 2396
  unreserved plus `/&=:@+$,` — so any path containing a semicolon, in the filename
  *or any parent directory*, hashes differently under Foundation's escaping and
  silently misses the cache for every file beneath it. Reimplement that character
  set and unit-test it with a semicolon fixture.
- Reveal-in-file-manager via `org.freedesktop.FileManager1.ShowItems`.
- **Acceptance**: MIME→icon-name resolution tests; thumbnail-cache path tests.

### JP-22 · Jetty · Hotkeys + power commands
**Branch** `claude/jp-22-hotkeys-power` · **Size** M

- `HotkeyBinder` with four implementations selected by **probing, never by desktop
  name**: extension keybinding, GlobalShortcuts portal, compositor config + a
  `jetty-cli` verb, GSettings custom-keybindings (documented, never auto-written).
  On 24.04 the expected portal error is `UnknownMethod`. Render the portal's returned
  `trigger_description` rather than Jetty's own `displayString`. Note **Hyprland is
  the exception** in the wlroots family: `xdg-desktop-portal-hyprland` implements
  GlobalShortcuts over its own protocol, while `xdg-desktop-portal-wlr` ships none
  through 0.8.1 (26.04) — so sway/river/Wayfire really are compositor-config only.
- `LinuxHotkeyTranslator`: **`keyLabel` is not a closed set** — the adversarial pass
  refuted that, and reading `HotkeyBinding.swift:56-79` confirms it. There are four
  branches, and the last is `return "Key \(event.keyCode)"`: a raw Carbon virtual
  keycode inside a string, undecodable without a Carbon table.
  `HotkeyRecorder.swift:65-83` accepts any keyDown with ≥1 modifier, so F-keys,
  keypad keys and punctuation all reach it. The translator therefore needs three
  tables plus a rejection path:
  1. the 14 glyph labels → `BackSpace`/`Delete`/`Return`/`Tab`/`Escape`/arrows/
     `Home`/`End`/`Prior`/`Next`/`space` — mind the macOS glyph inversion, ⌫ is
     **BackSpace** and ⌦ is **Delete**;
  2. ASCII letters lowercased, punctuation and digits via `xkb_utf32_to_keysym`;
  3. the AppKit private-use block **U+F704…U+F726 → F1…F35**, which arrives through
     the `chars.uppercased()` branch looking like an ordinary character.
  Map Carbon modifier bits to `CTRL/ALT/SHIFT/LOGO`. Everything else — every
  `"Key <n>"` label included — is unmappable: mark it needs-re-record rather than
  guessing at it.
- `PowerCommand.linuxAction` as a pure value beside `appleScript`; four of six go to
  `org.freedesktop.login1.Manager` with its `Can*` probes driving greyed-out items.
  Lock Screen uses `login1.Session.Lock()`, which GNOME Shell answers as the logind
  lock agent. The research also claimed `org.freedesktop.ScreenSaver.Lock()` is a
  declared-but-unimplemented stub on GNOME; that one is **[U]** — it did not survive
  into the verified set, and gnome-shell has owned that bus name for years. Check it
  empirically (`gdbus call --session --dest org.freedesktop.ScreenSaver …`) before
  ruling it out, and keep it as a tested fallback if it works, since some desktops
  register no logind lock agent.
  Only Log Out branches per desktop, resolved by asking the bus who owns
  `org.gnome.SessionManager` / `org.kde.Shutdown`.
- Three corrections from the adversarial pass, each a "the call succeeds but nothing
  happens" trap of the same class `PowerCommands.swift:116-123` already documents for
  macOS:
  - `Session.Lock()` is **not** unconditional. gnome-shell's `screenShield.js`
    `lock()` returns immediately, logging "Screen lock is locked down, not locking",
    when `org.gnome.desktop.lockdown disable-lock-screen` is set. Report that to the
    user rather than showing a lock that did not happen.
  - The `Can*` probes are necessary but not sufficient: logind picks the polkit
    action per situation (`*-multiple-sessions` when another user is logged in,
    `*-ignore-inhibit` when an inhibitor is held), so a command that probes as
    available can still raise an auth prompt or fail.
  - **logind has no *graceful* log-out.** `Session.Terminate()` kills the session
    outright — no session save, no inhibitor check, no confirmation — so the
    desktop's own session manager is the real implementation and `Terminate` is a
    last-resort fallback, not an equivalent.
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
- **Stand up a headless compositor job here**, and let every later frontend item
  inherit it. The adversarial pass found that a GitHub runner ships no compositor
  *preinstalled* but is one apt install away: **sway under
  `WLR_BACKENDS=headless WLR_RENDERER=pixman` runs in a bare container and advertises
  `zwlr_layer_shell_v1` v4**. So the layer-shell tier is testable in CI — anchoring,
  exclusive zone, keyboard mode, the sliver's enter event — not merely compiled,
  which is a much better net than this plan first assumed.
- **Acceptance**: `LinuxScreenSpace` tests green; the surface comes up anchored under
  headless sway in CI; manual verification on real KDE/Sway sessions documented
  honestly in the PR (for the things headless cannot show — fullscreen stacking,
  fractional scaling).
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
  Jetty's central behaviour. **First establish whether it is reachable by a
  third-party client at all** — the name matches KWin-internal API on its layer-shell
  implementation, and no `*screen_edge*` request appears in wlr-protocols or KDE's
  wayland-protocols — then evaluate it before hand-rolling the sliver on KDE. If it
  is internal-only, the sliver is the answer on KDE too.
- **Acceptance**: policy tests reused unchanged; manual reveal verification on KDE
  and Sway, including over a fullscreen window.

### JP-27 · Jetty · Drag & drop
**Branch** `claude/jp-27-dnd` · **Size** M

- `GtkDropTarget` on the dock and the sliver accepting `GdkFileList` / `text/uri-list`
  with **`GDK_ACTION_COPY` only**.
- **This reverses the corpus's COPY|MOVE guidance, which the adversarial pass
  refuted.** GTK4's `gtk_drop_target_accept` is a plain non-empty intersection
  (`gtk/gtkdroptarget.c`, 4.14.2 as shipped on noble), so a COPY-only target does
  accept a Nautilus drag whose preferred action is MOVE — the wholesale rejection the
  corpus warns about is not GTK4's behaviour. And declaring MOVE is the *riskier*
  choice here: `make_action_unique` still picks COPY when both are in the
  intersection, so it buys nothing, while a `gdk_drop_finish()` that reports MOVE is
  exactly what tells the source to **delete the original** — a data-loss hazard on
  the Trash tile, which is the one target where a wrong action is unrecoverable.
  Add a test asserting the finish action.
- Drop on the sliver reveals then pins (the `DragRevealSensorView` analogue); drop on
  a folder tile moves; drop on Trash calls `gio trash`; reorder within the strip
  reuses JP-06's `DockDragPolicy`.
- **Acceptance**: target-resolution tests reusing the pure drag policy; a real
  Nautilus drop verified manually and recorded.

### JP-28 · Jetty · Popovers: folder stacks, context menus, the Jetty Menu
**Branch** `claude/jp-28-popovers` · **Size** L

- **Spike this first, before the rest of the item.** All three of these features
  become `xdg_popup`s parented to a *layer* surface. `zwlr_layer_surface_v1.get_popup`
  has existed since protocol **version 1**, so that is not the gate; the
  version-gated piece is `keyboard_interactivity = on_demand`, which the Jetty Menu
  surface needs. Check the advertised version at bind time and degrade deliberately
  (the menu can take `EXCLUSIVE` while open — and must give it back on close, by
  unmapping the surface or resetting `keyboard_interactivity` to `NONE`; a reused
  surface left mapped holds the compositor's keyboard and locks the user out of their
  own apps) rather than silently losing type-to-find
  on an older compositor. The combination is unverified on our target compositors. If `GtkPopover` on a layer
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
  and LCD renders are pure functions of the formatter output) — but "deterministic"
  only holds once the text path is pinned, so vendor the fonts in the repo, isolate
  fontconfig with `FONTCONFIG_FILE` and fixed hinting/antialiasing, and draw the
  seven-segment digits as cairo geometry rather than text. Otherwise the baselines
  drift with every container rebuild and the safety net becomes a chore. Builds in CI.

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
  `gtk_application_id`, which arrives asynchronously on Wayland — that is the default
  and the only one that works for the shipped configuration. `Meta.WaylandClient` owns
  only clients the extension itself spawned, and JP-34 starts `jettyd` from a systemd
  user unit, so keep it as a dev-session launch path, not an alternative.
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
  (`NoDisplay=true`), icons, the systemd user unit, and **the extension unpacked
  under `/usr/share/gnome-shell/extensions/<uuid>/`** — not a zip under
  `/usr/share/jetty/`, which GNOME Shell never scans, so nothing would appear in the
  Extensions app for JP-33's first-run flow to deep-link to.
  `lintian --fail-on error`.
- Dependencies resolve via `dpkg-shlibdeps`; add `libglib2.0-bin`,
  `dbus-user-session`, `hicolor-icon-theme`, `adwaita-icon-theme`,
  `shared-mime-info`, `desktop-file-utils`; `upower`, `xdg-desktop-portal-gnome |
  xdg-desktop-portal-kde` and `xdg-utils` as Recommends; a file manager as Suggests.
- **Acceptance**: the `.deb` installs and the dock runs on a clean Ubuntu 26.04 VM;
  built and lintian-clean in CI; attached to releases.

### JP-35 · Jetty · Linux update flow + documentation
**Branch** `claude/jp-35-updates-docs` · **Size** M

- The existing `UpdateChecker`/`UpdateDownloader` port, but **split the install
  strategy by tier** — the macOS in-place semantics do not survive a `.deb`. A
  packaged `jettyd` runs unprivileged out of `/usr/bin`: it cannot write there, and
  if it somehow did it would desynchronise dpkg's database, fail `debsums`, and be
  silently reverted by the next `apt upgrade`. So: an AppImage (user-writable) keeps
  the `.bak` rotation, corrupt-quarantine and newer-version-refusal semantics exactly
  — they are tested and load-bearing — while a `.deb` install runs the same version
  comparison and asset-integrity checks and then **hands the downloaded `.deb` to the
  package system** rather than installing it itself.
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
