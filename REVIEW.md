# Jetty Review

Updated 2026-07-17 against `main @ c0ccfa7`, folding in the k3 review session
(`k3.md` — findings B1–B30, P1–P10, V1–V8, U1–U12 and PRs #46–#54).

This is the active code-review backlog for Jetty. It consolidates the unresolved work
from the former `ANALYSIS.md`, `fable-is-awesome.md`, `sol.md`, `k3.md`, and earlier
versions of this document. Completed findings and review-session history have been
removed; Git history and merged pull requests preserve that detail.

The current review was static because the review host has no Xcode or macOS GUI session.
PRs #32-33 and #35-45 were re-reviewed against `main` on 2026-07-11 and merged; #32 was
hand-resolved to keep the native `DockContextMenuSource` context menu and the
`accessibilityActions` block that superseded its SwiftUI `.contextMenu` and default
accessibility action. Treat the merged result as unverified until it builds and passes
tests on macOS CI.

[Pending PRs](#pending-pull-requests) | [Critical](#critical) |
[High](#high-priority) | [Performance](#performance-and-architecture) |
[Correctness and UX](#correctness-and-ux) | [Product gaps](#product-gaps) |
[Validation](#profiling-plan) | [Guardrails](#standing-risks-and-guardrails)

## Priority summary

1. Establish a signed, notarized release and authenticated update chain.
2. Require first-run consent before changing the global system Dock.
3. Finish the Trash pipeline off the main thread and report real operation outcomes.
4. Make hit testing, magnification, overflow, and popover placement use one geometry
   model.
5. Correct System Monitor data sources and execution context.
6. Make update, AppleEvent, and destructive actions asynchronous, visible, and
   focus-safe.
7. Provide operational accessibility, not labels alone.
8. Finish display identity, persistence safety, Window Peek, and Now Playing lifecycle
   work.

## Pending pull requests

These implementations are not on `main` and therefore remain unresolved. The residual
column is work the PR deliberately does not cover. (k3 PRs #46–#54 have since been
merged or superseded; only #58 remains open.)

| PR | Implemented scope | Residual work |
|---|---|---|
| [#34](https://github.com/L-K-M/Jetty/pull/34) | Exact display reverse mapping, collision-resolved entries, in-session key reservation, live Settings updates | Blocked on rework: monotonic key reservation drifts a reconnected display's base UUID to `#2`, `#3`, … (new `CGDirectDisplayID` + new `NSScreen` miss both reverse maps while the UUID stays reserved), orphaning persisted per-display settings. The reverse-mapping and DisplaysView halves are sound and worth resubmitting; see the PR review comment. |
| [#58](https://github.com/L-K-M/Jetty/pull/58) | Trash tile rebuilt: real CoreTypes can artwork, tiered exact state (home probe → preflighted Finder Automation → honest default), Permissions consent row, timeliness triggers; research in TRASH.md | Device verification; background Empty Trash/move outcomes (H2); per-volume Trash beyond the home directory |

## Critical

### C1. Authenticate updates end to end

**Paths:** `Jetty/Updates/UpdateDownloader.swift`, `UpdateChecker.swift`,
`GitHubRelease.swift`

The downloader trusts HTTPS and an unauthenticated GitHub response. PR #38 detects a
byte-count mismatch, but size is not proof of publisher or content identity.

Required end state:

- Verify the current temporary staging path has owner-only permissions, or create an
  explicit `0700` staging directory.
- Enforce expected scheme, host, redirects, extension, and content type.
- Publish and verify a signed SHA-256 manifest or detached signature.
- Authenticate the asset before revealing it. If installation/extraction is added,
  verify the app's designated requirement, Team ID, entitlements, and notarization
  before replacement.
- Keep quarantine and remove all instructions that bypass Gatekeeper.
- Test bad signatures, wrong Team ID, malformed, truncated, oversized, redirected, and
  time-of-check/time-of-use cases.

### C2. Replace the unsigned release workflow

**Paths:** `.github/workflows/release.yml`, `README.md`

The workflow disables normal signing, publishes an ad-hoc-signed artifact, and documents
quarantine removal. Release jobs must fail closed without Developer ID and notarization
credentials, then verify signing, hardened runtime, entitlements, notarization, staple,
DMG integrity, and a mounted-app smoke test before publication.

### C3. Pin the release supply chain

**Paths:** `.github/workflows/ci.yml`, `.github/workflows/release.yml`,
`.github/workflows/zai-code-review.yml`, `scripts/build.sh`, `scripts/release.sh`

Pin third-party Actions to full commit SHAs, pin downloaded tools and checksums, and
verify the shared release engine's version and identity. The write-capable
`pull_request_target` review workflow deserves the same pinning even though it does not
currently check out PR code. Publishing artifact hashes, provenance, and an SBOM is the
follow-on auditability layer.

## High priority

### H1. Require a safe Dock handoff and reliable recovery

**Paths:** `Jetty/AppDelegate.swift`, `Jetty/Model/Preferences.swift`,
`Jetty/Dock/DockController.swift`, `PLAN.md`

First launch can change `com.apple.dock` before instruction or explicit consent. Present
Try Jetty, Keep Apple Dock Visible, and Quit choices; teach the configured reveal edge;
require one successful reveal before hiding Apple's Dock; and persist onboarding
separately from `dock.json`. Keep Restore System Dock visible and test interrupted first
launch, crash, and relaunch recovery.

For established installs, detect contradictory management bookkeeping such as managing
without captured state or after an explicit opt-out. Provide a force-restore path that
does not depend on a valid captured preference snapshot.

### H2. Finish the Trash pipeline off the main thread and expose real outcomes

**Paths:** `Jetty/Apps/TrashLocations.swift`, `TrashMonitor.swift`, `AppLauncher.swift`,
`Jetty/Dock/DockController.swift`, `DockModel.swift`

**Resolved by PR #58 (pending) / researched in TRASH.md:** two root causes were at
play — the legacy named Trash images don't resolve on macOS 26, and enumerating
`~/.Trash` requires Full Disk Access (TCC), so the probe reported `.unknown` →
stuck-empty can. PR #46's workspace-icon detour rendered a generic *folder* and was
reverted. PR #58 uses the CoreTypes can artwork and a tiered, prompt-free state
pipeline (home-Trash probe → silently preflighted Finder Automation `count` → honest
empty-can default with a one-click consent flow in Settings → Permissions), cached
and recomputed on watch events, own actions, and reveal.

Remaining:

- Run volume discovery/state reads (still in `TrashMonitor.arm` per parent event)
  and file moves/Empty Trash on one serialized utility worker; moves currently loop
  `FileManager.trashItem` synchronously on the main thread with log-only failures.
- Return moved URLs and per-item errors; distinguish accepted, complete success,
  partial failure, and total failure. PR #32's pulse is accepted-action feedback,
  not success feedback.
- Explain denied Finder Automation and restore prior focus on success, cancel, or error.
- Publish state for the accessibility work tracked in H7 (e.g. "N items" when the
  probe is readable; the icon itself no longer carries state information).

Add dependency-injected watcher, volume, probe, partial-move, permission, and
event-to-scan-count tests. Device-test home and external Trash, vnode replacement, mount/unmount,
sleep/wake, metadata-only folders, unreadable paths, and large contents.

### H3. Use one authoritative Dock geometry and hit-test model

**Paths:** `Jetty/Screens/DockLayout.swift`, `Jetty/Dock/DockPanelController.swift`,
`DockView.swift`, `DockTileView.swift`, `MagnificationCurve.swift`

The visual strip, panel frame, scaled tiles, glow, drag targets, hover labels, scroll
offset, and child-panel anchors are derived independently. Consequences include
transparent headroom intercepting input, a high-level edge sensor creating dead strips,
overlapping magnified neighbors, clipped end tiles, wide vertical
widgets escaping glass, invisible drag-out, and misplaced overflow anchors. (Wrong-edge
and clipped hover labels were fixed by PR #47, the magnification headroom snap-off and
overflow glow-dot lead by PR #49; the overflow-state popover-anchor desync and the
`inset > 0` strip-frame stretch found by k3 remain.)

Build one immutable geometry snapshot containing visible glass, presentation tile
frames, cumulative neighbor displacement, overflow offset, headroom, and hit regions.
Use it for rendering, panel hit testing, z-order, glows, reorder, drag-out, scrolling,
and popover anchors. Return no hit outside visible glass or an actual presented tile.
Verify the drag sensor can remain mouse-transparent and lower its level where possible.
Device-test whether the main panel and child panels can sit below real pop-up menus while
remaining visible over normal/fullscreen windows. Define offset semantics at leading and
trailing extremes so a legal slider direction does not silently clamp to a no-op. PR #33
restores the pure revealed frame and removes one duplicate recomputation; it does not
provide authoritative hit testing. (`DockLayout.keepRevealedFrame` now bridges the
inset gap to the physical edge, so the post-#33 reveal/hide flapping follow-up is
resolved.)

### H4. Correct System Monitor values and execution context

**Paths:** `Jetty/Widgets/SystemStats.swift`, `LiveSystemStats.swift`,
`SystemMonitorWidgetView.swift`, `SystemMonitorGaugeView.swift`,
`SystemMonitorScopeView.swift`, `SystemMonitorLEDView.swift`

The CPU label is normalized load average rather than CPU utilization, network counters
are 32-bit, and all reads occur from a main-thread run-loop timer. PR #35 corrects
elapsed-time rate seams but not the sources.

Use `HOST_CPU_LOAD_INFO` deltas and `NET_RT_IFLIST2` 64-bit counters, reset baselines when
interfaces change, sample on a utility queue, and publish one atomic equatable snapshot.
Track CPU/RAM, network, and battery demand separately. Use a slower battery-only cadence,
pause expensive work while every panel is hidden, and refresh immediately on reveal.
Add pure tests for CPU deltas, variable sample intervals, 64-bit counters, interface
replacement, backward/wrapped counters, and long suspension.

### H5. Make persistence failure-safe and visible

**Path:** `Jetty/Store/DockStore.swift`; recovery controls are a proposed Settings
surface.

Current backup rotation removes the old backup before proving its replacement exists.
PR #39 fixes that narrow failure mode, with two deliberate trade-offs to revisit: a
failed rotation now aborts the primary write too (log-and-continue would keep new edits
at the cost of a stale backup), and orphaned `.dock.json.bak.tmp-*` siblings are never
swept if the process dies mid-rotation. Remaining work is to snapshot and write on one
serial I/O queue (today `saveNow` does read-decode-copy-encode-write on the main queue,
per slider tick), keep a synchronous termination flush, and expose whether primary,
backup, or defaults loaded. Show persistent save errors, clearly disable future-version
read-only mutations, and offer backup export and restore when recovery occurred. The
"lossy" decode only protects element-level failures — a wrong-shaped *container*
(`items` as a dictionary, `version` as a string) still throws the whole load away into
a silent fresh-document fallback with no recovery notice (k3 B30): decode each field
with `try?` + default.

### H6. Make external actions asynchronous, visible, truthful, and focus-safe

**Paths:** `Jetty/Menu/PowerCommands.swift`, `MenuCommand.swift`,
`JettyMenuController.swift`, `Jetty/Dock/DockController.swift`,
`Jetty/Updates/UpdateChecker.swift`, `Jetty/Settings/AboutView.swift`,
`Jetty/Settings/MenuView.swift`, `Jetty/Settings/PermissionsView.swift`

AppleEvents and destructive actions were synchronous and denied Automation was logged
after the initiating UI disappeared; PR #51 moved AppleScript execution off the main
thread and made the destructive confirmation and update alerts render above the
`.popUpMenu` menu panel. Still open: automatic update checks can activate a modal alert
over another app, AppleEvent *results* are invisible, and denied Automation has no
recovery path. Extract and reuse Jetty Menu's existing prior-app capture and Finder
fallback for Dock alerts and updater UI. Execute AppleEvents on one serial worker
returning `Result`, keep or reopen visible status, show proactive Automation status and
recovery in Permissions, and restore focus for every outcome. Verify whether restart,
shutdown, and logout produce a second OS confirmation, then retain exactly one
confirmation prompt.

Automatic update checks must notify or defer instead of activating Jetty; manual intent
must queue or upgrade an in-flight background check; download progress, saved path, and
failures must be visible.

Lock Screen is part of this contract: inspect `SACLockScreenImmediate`'s return value.
Missing symbol or failure must be visible. A screen-saver fallback must be labeled Start
Screen Saver because it may not lock immediately. Update Settings copy and command tests
to match the final behavior.

### H7. Complete accessibility parity

**Paths:** `Jetty/Dock/DockTileView.swift`, `Jetty/Widgets/`,
`Jetty/Settings/AngleDial.swift`, `AppearanceView.swift`, `MenuView.swift`,
`HotkeyRecorder.swift`, `Jetty/Hotkeys/`

Tiles and widgets do not expose most visible dynamic information. Settings has drag-only
or glyph-only controls without complete semantics. Main exposes named tile context
actions; PR #32 adds default tile activation and hides separators. Dynamic values remain.

- Expose dynamic clock, Trash, battery, weather, CPU/RAM/network, media, world-clock, and
  Pomodoro values and hints.
- Keep AngleDial's numeric degree value and add adjustable actions; expose units on the
  remaining custom controls.
- Label and select glyph controls; give sliders unit-bearing values.
- Add a Carbon-hotkey-driven keyable Dock Navigator for arrows, Return, and context
  actions without activating the core panel.
- Test VoiceOver, Full Keyboard Access, Accessibility Inspector, Reduce Motion, Reduce
  Transparency, Increase Contrast, and Differentiate Without Color.

### H8. Preserve durable display identity

**Paths:** `Jetty/Screens/DisplayRegistry.swift`, `Jetty/Settings/DisplaysView.swift`,
`Jetty/Store/DockStore.swift`

Current collision keys do not reverse-map reliably; PR #34 fixes that in-session mapping
and Settings freshness. Durable placement for duplicate or UUID-less hardware across
relaunch still needs investigation of public stable discriminators such as available
vendor, product, or serial characteristics. Expose already-preserved disconnected
display records in Settings with a Forget action, and document session-only fallback
when hardware is genuinely indistinguishable.

### H9. Finish Window Peek lifecycle, permissions, and exact-window behavior

**Paths:** `Jetty/Windows/AppWindows.swift`, `WindowPeek.swift`,
`WindowPeekController.swift`

PR #36 removes duplicate initial listing and cancels obsolete capture generations;
PR #53 bounds AX messaging (0.5 s), fetches AX titles only when needed, hands the
hover-time listing to the model, and detaches the refresh task. Remaining work:

- Refresh topology more slowly or from events; the 1 s re-capture loop still runs
  while the popover is up.
- Capture only thumbnails visible in the popover viewport, near displayed pixel size.
- Merge AX windows so minimized windows appear and can be restored (k3 B27:
  minimized-only apps currently show "No open windows" with no un-minimize path).
- Hide or disable minimize controls without Accessibility and explain recovery.
- Remove nested button targets and inspect AX operation results.
- Surface AX trust, private-symbol availability, exact-match failure, and operation
  errors.
- Derive popover height from fitting content, including permission guidance.

### H10. Finish Now Playing lifecycle and player identity

**Paths:** `Jetty/MediaRemote/MediaRemoteBridge.m`,
`Jetty/Widgets/NowPlayingService.swift`, `NowPlayingWidgetView.swift`,
`Jetty/Dock/DockController.swift`

PR #37 closes known timeout, lookup, and dispatch-source lifecycle seams. Replace
fresh-controller polling with one long-lived controller or MediaRemote notifications, share
one cadence across displays, suspend while hidden, and preserve fail-closed isolation.
Carry the originating player's bundle identity so clicking Spotify or another source
does not always open Apple Music.

## Performance and architecture

### P1. Coalesce preference, model, and store publication

**Paths:** `Jetty/Model/Preferences.swift`, `Jetty/Dock/DockModel.swift`,
`DockController.swift`, `Jetty/Store/DockStore.swift`

Split broad render domains or pass small equatable configurations, batch preset and
store mutations, publish one model snapshot, and perform one save/rebuild/reconciliation
per operation. Diff geometry before relayout and debounce continuous persistence where
safe. Cache tile centers and reorder extents until structure changes, calculate pointer
results once per event, and coalesce raw motion to display cadence. Resolve first-use app
icons asynchronously, skip relayout for active-state-only changes, and invalidate panel
shadows only when frame or reveal state changed.

### P2. Suspend hidden work and bound image costs

**Paths:** `Jetty/Dock/EdgeHoverMonitor.swift`, `DockController.swift`,
`Jetty/Widgets/LiveSystemStats.swift`, `NowPlayingWidgetView.swift`,
`Jetty/Common/IconCache.swift`, `TileAccent.swift`,
`Jetty/Menu/JettyMenuModel.swift`, `Jetty/Settings/ItemsView.swift`

Publish visibility through a shared coordinator. Suspend expensive services while all
panels are hidden and start mouse monitors only when edge reveal has demand. Replace
synchronized icon TTL expiry with stale-while-revalidate, bound menu and accent caches,
extract accents on a background queue, key by icon identity/version, and cache Settings
row icons.
Make mutable static image caches actor-isolated or synchronized before moving extraction
to a background queue. Downsample user images before decoding; durable custom-image
lifecycle belongs to U4.

### P3. Cancel and consolidate folder-stack work

**Paths:** `Jetty/Stacks/FolderStack.swift`, `FolderStackController.swift`

Make enumeration and icon work cancellable during traversal, metadata, sort, and load.
Return explicit error and truncated states instead of conflating unreadable with empty;
show Couldn't Read and Showing First 128. (The broken Escape monitor — which could only
steal Escape from the Jetty Menu/Settings, never dismiss the stack — was removed by
PR #54; if Escape dismissal is wanted, it needs a key-capable panel design.)

### P4. Remove duplicate Jetty Menu work

**Paths:** `Jetty/Menu/AppIndex.swift`, `AppSearch.swift`, `JettyMenuModel.swift`,
`RecentAppsStore.swift`

PR #50 removed the per-keystroke ICU re-sort of the whole index (the empty query now
reuses AppIndex's own sorted order), the per-keystroke UserDefaults recents reads
(snapshotted per show), and the per-keystroke `NumberFormatter`. Remaining: avoid the
initial double app scan, cancel/coalesce reloads, cache directory snapshots
and bundle metadata, publish one menu state, and resolve row icons asynchronously
(first paint still hits `NSWorkspace.icon(forFile:)` synchronously, into an unbounded
cache). Ignore hover selection caused only by rows scrolling under a
stationary pointer, and restore key/search focus after a cancelled destructive alert.

### P5. Make bookmark and launch actions consistent

**Paths:** `Jetty/Store/BookmarkResolver.swift`, `Jetty/Apps/AppLauncher.swift`,
`Jetty/Dock/DockController.swift`, `Jetty/Menu/JettyMenuController.swift`

Route click, drag-to-open, and Show in Finder through one resolved URL. Use cheap hover
eligibility and resolve after dwell on a background queue with `.withoutUI` and
`.withoutMounting`; mount only after explicit action. Consume `NSWorkspace` completion
results, record recents only after success, preserve exact URL/PID identity for duplicate
app copies, activate an already-running app instead of blindly opening it, and show
nonintrusive success or error feedback.

## Correctness and UX

### U1. Make shortcut and launch-at-login failures actionable

**Paths:** `Jetty/Settings/HotkeyRecorder.swift`, `GeneralView.swift`,
`Jetty/Hotkeys/CarbonHotkey.swift`, `Jetty/Model/Preferences.swift`

Suspend both Jetty hotkeys while either recorder is active, reject duplicate bindings,
and show Carbon or OS-owned registration failures inline (k3 B17: today `register`
returns false and Settings still shows the shortcut as set). The recorder also swallows
⌘Q/⌘W/⌘, and Tab while recording, letting users register over the app's own menu
equivalents (k3 B25). Represent every
`SMAppService` status, provide Login Items recovery, unregister pending requests when
toggled off, and avoid unexplained Boolean snapback.

### U2. Coordinate dock, child-panel, menu, and drag lifetimes

**Paths:** `Jetty/Dock/DockPanelController.swift`, `DockController.swift`,
`DockView.swift`, `Jetty/Stacks/FolderStackController.swift`,
`Jetty/Windows/WindowPeekController.swift`, `Jetty/Menu/JettyMenuView.swift`

PR #48 keeps the dock revealed while a stack/peek popover is open. Remaining: keep it
revealed while an alert or drag interaction is active, and add a hover corridor between
dock and child panel. Render drag-out as an
unclipped outward-only ghost with a Remove cue and Undo. Device-test reorder versus
overflow scrolling and use long-press or explicit move actions if gestures conflict. A
subtle glass stem or glow can visually tether an open child panel to its source tile.

Two k3 findings belong to this lifetime story: the edge drag-reveal sensor answers
`.copy` to any file drag immediately, so a drag aimed at the bottom edge of a maximized
*other* app's window gets consumed and pinned (accept only after a ~300–500 ms dwell —
k3 B21); and dropping files onto a **folder tile** pins them to the dock where Dock
muscle memory expects move/copy into the folder (decide the semantics — k3 U5).

### U3. Honor display accessibility settings and visual contrast

**Paths:** `Jetty/Dock/DockTileView.swift`, `DockPanelController.swift`,
`Jetty/Common/GlassBackground.swift`, `Jetty/Widgets/AnalogClockFace.swift`,
`SystemMonitorWidgetView.swift`

Make Reduce Motion, Reduce Transparency, Increase Contrast, and Differentiate Without
Color reactive. Reduce Transparency must use an opaque semantic high-contrast surface,
not another blur; preserve meaningful distinctions between Regular, Clear, and Tinted
fallbacks. Under Reduce Motion, replace scaling, reorder motion, and animated widget/menu
transitions with static emphasis and short fades. Under Differentiate Without Color, add
labels, shapes, or line styles instead of relying on hue. Improve low-contrast clock
hands and Jelly outlines. Geometry-owned labels and transparent headroom are covered by
H3; additional face/monitor polish is listed under Low-priority debt.

### U4. Use one source of truth for Settings and imported assets

**Paths:** `Jetty/Settings/GeneralView.swift`, `DisplaysView.swift`, `ItemsView.swift`,
`AppearanceView.swift`, `Jetty/Model/Preferences.swift`, `DockAnchor.swift`

Publish shared numeric range constants so persisted values and controls agree. Add Reset
to Global Default for a disabled display's retained override. PR #41 scopes controls and
loading to supported tile kinds; for those kinds, copy or bookmark the image into
Application Support, downsample it, and clean it on clear/removal. Preset export should
derive or request a name, write atomically, use a neutral operation-error state, and
clear stale banners after a successful export.

### U5. Make data-source identity and age visible

**Paths:** `Jetty/Menu/CurrencyService.swift`, `JettyMenuView.swift`,
`Jetty/Settings/MenuView.swift`, `Jetty/Widgets/WeatherWidgetView.swift`,
`WeatherService.swift`

PR #40 makes currency access intent-driven. Two small follow-ups from its merge: Return
is swallowed forever for valid-ISO-but-provider-unsupported codes (web search becomes
mouse-only there), and same-code identity conversion is only special-cased for USD, so
"100 eur to eur" offline shows the loading state instead of the trivial answer. Add
provider disclosure and opt-out, validate HTTP status and payload date, persist
source/date, and label stale rates. Replace weather
coordinate `(0,0)` as the unconfigured sentinel with explicit migrated state; show the
selected location and support city input through forward geocoding. Add apparent
temperature, humidity, wind, and daily high/low to tooltip and accessibility output.

### U6. Provide an intentional empty-dock recovery surface

**Paths:** `Jetty/Screens/DockLayout.swift`, `Jetty/Dock/DockController.swift`,
`Jetty/Settings/ItemsView.swift`

Do not reveal a blank interactive glass slab. Offer Drop Apps Here, Open Settings, and
Restore Defaults, or keep the visual panel hidden until a file drag reaches the edge.

### U7. Localize UI and parsing

Add a String Catalog, pseudolocalization, and RTL coverage. Localize hardcoded UI,
seeded labels, command tokens, and LCD meridiem output while preserving the existing
locale-aware date/time formatting. Parse locale decimal separators while retaining `.`
aliases. Detect the default browser instead of assuming Safari.

## Low-priority debt

| Area | Remaining action |
|---|---|
| Carbon hotkeys | Replace per-instance event handlers and `passUnretained` lifetime assumptions with one app-wide handler. |
| Update scheduling | Add ETag/`If-None-Match`, jitter, backoff, and GitHub rate-limit awareness. |
| Running apps | Observe runtime activation-policy changes and remove the full-scan bundle fallback. |
| Caches | Consolidate duplicate LRU implementations and add explicit invalidation. `TileAccent` is keyed by tile id only — stale after a custom-icon change; key by `iconCacheKey` and bound it (k3 B22). |
| World Clock | Canonicalize aliases such as `US/Eastern` to a representative city, add day/night state, and provide a grouped searchable picker. |
| Clock and monitor polish | Cache static dial furniture, add analog date and world-clock faces, blink the LCD colon, split network traces, add tested peak hold/scope sweep, align Color Time, and animate gauge needles/over-rev treatment. LED segments cramp at small tile sizes — scale segment count with height (k3 V6). |
| Pomodoro | Inject the clock and sleep/wake notification source for tests, reuse the existing defaults injection, and add a completion notification (completion is sound-only today — k3 U8). |
| Vertical layout | Give separators a compact along-axis extent and define inward clock growth. |
| Dead code | Remove or reconnect `DockLayout.hiddenFrame`/`edgeReveal` and dead divergent `AppLauncher` helpers; `DockPanelController.toggle()` is also unused (k3). |
| Poof | Correct the comment that promises sound or deliberately add one. |
| Folder stack | Add per-stack Name/Date/Kind sorting, Quick Look, and URL drag-out. |
| Widget visuals | Weather glyph `.multicolor` ignores the tint modifier (dead code — use `.hierarchical`, k3 V4); now-playing glyph uses raw tint (invisible on dark glass — reuse the monitor's white-lift; static `pause.fill` reads as a button, k3 V5). |
| Single-instance guard | A simultaneous double-launch can terminate *both* instances (each sees the other as older); prefer the oldest `launchDate` or a claim-based guard (k3 B26). |
| Responsiveness monitor | The "Not Responding" badge carries over by bare pid, so a relaunched process reusing the pid inherits it for up to ~30 s; key state by pid + launchDate (k3 B28). |

## Product gaps

These are features or documented promises, not current regressions:

- Spotlight/`NSMetadataQuery` app discovery beyond fixed directories, merged by bundle
  ID and path with visible indexing state.
- One keyboard selection model spanning apps, calculations, conversions, commands, web
  search, and power actions; typed power commands, `Command-1...9` result jumps,
  `Command-Return` web search, explicit result-copy shortcuts, and semantic power-row
  typography.
- Recents management, Clear/Remove/Incognito, and configurable web-search provider.
- Window switching in Jetty Menu; app-row Reveal, Get Info, Open With, and process
  actions; direct URL/host detection rather than web-searching URLs.
- Offline Dictionary Services for `define`, live `time in` results, and Tab-to-swap
  conversions.
- Drag a Jetty Menu result onto the dock to pin it.
- Settings search, per-pane reset/undo, saved presets, live preset/widget previews, and
  Add/Remove tile actions from widget sections.
- After C1/C2, one-click verified Install and Relaunch, a post-update What's New panel,
  a verified-publisher badge, and a verified-updates pane showing channel, signature,
  and installed version/date. Consider optional signature preflight before launching a
  pinned app only after the release trust model is established.
- Additional converter families and named CSS colors.
- PLAN-described Escape hide, reveal sliver, configurable hide-after-launch,
  corrupt-store restore offer, and system-Dock reappearance detection. Implement them or correct
  PLAN so they are not current promises.
- Badges/unread counts, taskbar or multi-row mode, and deeper Stage Manager behavior are
  later roadmap items.

## Delight roadmap

Highest-value ideas and dependent follow-ons:

- A display-topology editor with disconnected-display management.
- Restrained Trash wobble or gulp only after confirmed success, Empty Trash poof, and an
  on-demand-only count/size X-ray (PR #58 makes the can truthful, unblocking this;
  the Finder-Automation count is already available for it).
- Now-playing upgrade: album-art thumbnail, animated equalizer bars while playing, and
  a Play/Pause context action via `MRMediaRemoteSendCommand`; carry the source player's
  identity so the tile opens the right app (H10).
- Sweep-second-hand option for the analog clock faces (`TimelineView(.animation)`).
- Option-hover expansion for battery time-to-full/empty, weather feels-like/high/low,
  Pomodoro controls, and media artwork.
- Pomodoro menu-bar progress and multi-city world-clock day/night personalities.
- Pomodoro session heat map, named timers, and stopwatch mode.
- Theme cards previewed over light, dark, and busy wallpaper with contrast warnings and
  an exported preview image beside preset JSON.
- Theme eyedropper/screen sampler, per-item accent overrides, and hotkey chords.
- Opt-in sunrise/sunset preset switching and per-display appearance personalities.
- `jetty://` reveal, menu, preset, and Pomodoro actions for Shortcuts.
- Per-tile launch hotkeys, scroll gestures, haptic alignment ticks, and a
  preference-gated `boing` Easter egg.
- Where Is My Dock edge pulses, one-time wake/display-recovery breathing, and an
  opt-in stuck-dock self-heal watchdog; use an edge-reveal heat map only as a diagnostic
  tool rather than background telemetry.
- Finder-style spring-loaded stack folders, last-hover spatial memory, command-hover
  path reveal, and bounce-on-launch.
- Continuous overflow zoom with hysteresis, temporary Option-hover face zoom, animated
  CRT flicker, and accessible Color Time narration.
- Window close controls, drag-out transient widgets, per-Space tile filters, and later
  Space assignment or floating mini-launcher experiments. Add optional frontmost-app
  Focus Dock filters such as a development tile set while Xcode is active.
- Opt-in local badge providers, sunrise/sunset, moon phase, AQI/UV, disk space, Time
  Machine, and next-calendar-event tiles with isolated permissions.
- Opt-in stock/crypto sparklines, GitHub stars, uptime probes, CPU/GPU temperature, and
  Focus/DND tiles with explicit data-source and privacy labeling.

## Profiling plan

For each run, record macOS/build/hardware, the Instruments artifact, baseline, target,
and pass/regression result.

1. Profile Trash discovery/state publication with many mounted, missing, and unreadable
   locations; confirm unrelated model rebuilds do not scan.
2. Exercise 20, 50, and 100 tiles with 125 Hz and 1,000 Hz pointers; measure body
   evaluations, Core Animation FPS, allocations, drag complexity, and animation commits.
3. Run Now Playing for an hour with no media and active media on one and three displays;
   count controllers, dispatch sources, and hidden-dock callbacks.
4. Exercise Window Peek with 10-30 windows while rapidly crossing tiles and closing;
   track WindowServer CPU, cancellation, image memory, and post-close publication.
5. Measure ten hidden minutes for each live-widget combination using Energy Log.
6. Apply a preset and drop 100 files; count preference notifications, model publications,
   saves, frame changes, and shadow invalidations.
7. Wait through icon-cache expiry, then activate apps and measure icon/accent work.
8. Sleep/wake with network history, external Trash, child popovers, and display changes.

## Manual release matrix

Record OS/hardware, build, result, date, and notes for each row. Use a documented
pairwise matrix unless a full cross-product is required for a release blocker.

- macOS 13 fallback and macOS 26 Liquid Glass; light and dark mode.
- Four edges, three alignments, inset 0/20/80, both offset directions, and Apple Dock
  managed or visible.
- One, two, and three displays; stacked seams; attach/detach while Settings is open;
  sleep/wake; fullscreen; Spaces; and reproducible display-identity collisions.
- Home/external Trash empty/full, mount/unmount, hidden files, metadata-only content,
  large contents, partial drop failure, denied Finder Automation, and vnode replacement.
- Magnification 1.0/1.5/2.5 with wide widgets, 250% clock, overflow, reorder, drag-out,
  labels, popovers, and file drop.
- VoiceOver, Full Keyboard Access, Reduce Motion, Reduce Transparency, Increase Contrast,
  and Differentiate Without Color.
- Window names/thumbnails with no permission and each permission independently granted;
  minimized windows; rapid hover; and close during capture.
- Signed release: mount the DMG, inspect contents, verify Team ID, entitlements,
  notarization, and quarantine; update; normal quit restore; force-termination recovery.

## Standing risks and guardrails

- The system Dock defaults technique is fragile across macOS releases. Preserve a clear
  Restore System Dock path and revalidate every OS update.
- Optional private APIs can drift. Keep them isolated, opt-in, dynamically resolved, and
  fail-closed.
- Do not reserve screen space or move other applications' windows.
- Do not add a global key monitor or event tap to the core path.
- Keep dock and ordinary child panels nonactivating; only Jetty Menu performs its
  deliberate focus handoff.
- Keep Liquid Glass gated to macOS 26 with an accessible fallback.
- Persist display identity plus edge/alignment/offset/inset, never raw window frames.
- Do not target the App Store or sandbox without a separate product decision.
- Do not kill or inject the system Dock as an ongoing strategy.
