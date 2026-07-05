# Fable is awesome — a fresh review of Jetty

*2026-07-05 · reviewed at `main @ 1741ef6` · Claude (Fable)*

A full fresh pass over the codebase: six parallel deep reviews (dock core /
screens / apps · widgets · Jetty Menu · settings / model / store / hotkeys ·
app infra / updates / windows / stacks / common / MediaRemote · tests / CI /
docs), cross-checked against `REVIEW.md` so that **everything below is new** —
none of these findings duplicate the existing C/H/M/L/F-\* backlog. Where a
finding needs a live GUI to confirm, it is marked *needs-device-verify*.

Special attention went to the code that landed **after** the last review
consolidation (the clock-face family + face zoom, and the system-monitor
styles), since it had never been reviewed. Verdict up front: the new zoom
geometry's *math* is exact (see [Verified clean](#verified-clean)) — but four
of its *integration seams* drifted, and three independent review passes
converged on the same overflow-mode bug, which is a good sign the findings
below are real.

Entries carry ids `FAB-…` (**B**ug, **P**erf, **V**isual, **U**X,
**S**ecurity, **A**11y, **T**ests/CI/docs, **D**elight). The
[implementation plan](#implementation-plan) at the bottom maps the entries I'm
confident about to branches; everything else stays here as backlog.

---

## Bugs

### FAB-B1. A second Jetty instance restores the system Dock out from under the first — and races its store
**`Jetty/AppDelegate.swift:56-60` + `Jetty/Dock/DockController.swift:83-97` + `Jetty/SystemDock/SystemDockController.swift:33`** · HIGH · confidence: high

The single-instance guard hands off to the running instance and calls
`NSApp.terminate(nil)` — but `applicationWillTerminate` is only guarded by
`isRunningTests`, so it still runs in the *duplicate*. `controller` is `lazy`,
so the terminating duplicate instantiates a fresh `DockController` just to
tear it down; `teardown()` ends with `if systemDock.isManaging {
restoreSystemDock() }`, and `isManaging` lives in **shared** `UserDefaults`.
Concrete failure: the user double-clicks the updater's copy in `~/Downloads`
(exactly the scenario the single-instance guard was built for) → the duplicate
activates the real instance, then on its way out **restores the system Dock
(`killall Dock`), clears `isManaging` and the captured prior state, and
disarms `reassertIfManaging()` for the whole session**. The same path calls
`store.flush()`, rewriting `dock.json` + rotating `.bak` from the duplicate's
stale snapshot, racing the live instance's debounced save.

**Fix:** set a `didStart` flag after the single-instance guard passes and make
`applicationWillTerminate` a no-op unless it's set. Belt-and-braces: make
`teardown()` a no-op when `start()` never ran.

### FAB-B2. `DockController.tileAnchor` missed the new zoom/widest-tile geometry — peek & stack popovers anchor off by up to ~55 pt
**`Jetty/Dock/DockController.swift:351,356`** · MEDIUM · confidence: high

The face-zoom commits updated three of the four mirrors of the tile-layout
math (`DockPanelController.contentSize`, `DockView.tileCenters`,
`DockView.activeGlows`) but not the fourth — `tileAnchor`, which places the
window-peek and folder-stack popovers. It calls `DockLayout.tileExtent`
**without** `clockWidthFactor` (so a 250 % clock is budgeted at 1.6× instead
of 2.38×: every tile after it is off by ~40 pt) and computes
`extra = (mag − 1) · base` without the `widestTileFactor` the other mirrors
now use (another ~18–20 pt of drift whenever a wide tile is present). Hover a
running app to the right of a zoomed clock or a now-playing tile and the peek
popover appears visibly detached from its icon.

**Fix:** pass the clock width factor into `tileExtent` and use
`DockLayout.magnificationAlongExtra(iconSize:magnification:widestFactor:)`
for the lead — ideally extract one shared pure helper so a fifth mirror can't
drift (see FAB-D1).

### FAB-B3. Overflow-scroll keeps the zoom-widened clock tile while rendering the unzoomed face
**`Jetty/Dock/DockTileView.swift:225-233` vs `Jetty/Dock/DockView.swift:299-301`** · MEDIUM · confidence: high (found independently by three review passes)

In the overflow-scroll state `DockView` passes `allowsClockZoom: false`, so
`ClockWidgetView` renders the face at 1× — but `DockTileView.tileWidth` (and
`DockView.clockWidthFactor`, used for slot extents/centers) still compute the
clock width from `effectiveClockZoom`. At 250 % the clock occupies a 2.38×
slab of empty glass in exactly the state where along-axis space ran out — and
the inflated width is itself part of what tips the dock *into* overflow.

**Fix:** thread `allowsClockZoom` into the width math so `tileWidth` and the
slot-extent/center math fall back to zoom 1 together (changing `tileWidth`
alone would desync the reorder-center map). Keep `contentOverflows` deciding
on the *zoomed* width so the overflow decision can't oscillate.

### FAB-B4. "Restore System Dock" clobbers the user's own Dock settings when Jetty never captured them
**`Jetty/SystemDock/SystemDockController.swift:79-101` + `Jetty/AppDelegate.swift:158-160`** · MEDIUM · confidence: high

`restoreSystemDock()` never checks that anything was captured. With
`manageSystemDock` off, `capturedPrior` is unset, so "prior autohide" reads as
`false` — the always-enabled menu-bar item then writes `autohide = false`,
deletes the user's own `autohide-delay`/`autohide-time-modifier`, and restarts
the Dock. A user who keeps their *own* Dock auto-hide on and clicks Restore
"just to be safe" gets their preference silently wiped.

**Fix:** when `capturedPrior` is unset, only remove Jetty's keys (never write
`autohide`), or early-return; disable/retitle the menu item when not managing.

### FAB-B5. Every launch runs `killall Dock` even when nothing needs to change
**`Jetty/SystemDock/SystemDockController.swift:53-58`** · MEDIUM · confidence: high

`hideSystemDock()` unconditionally writes the defaults and restarts the Dock,
even when they already hold exactly the values Jetty is about to write — the
normal case on every launch after the first. With launch-at-login, every
login kills and respawns the Dock (~1 s of dead Mission Control / Spaces
gestures, a visible flash on some machines) for zero effect.
`reassertIfManaging()` already has the right drift check; the launch path just
doesn't use it.

**Fix:** skip the writes + restart when
`autohide == true && delay ≈ largeDelay && timeModifier == 0` already hold.

### FAB-B6. Folder stacks treat any folder with a dot in its name as a file
**`Jetty/Stacks/FolderStackController.swift:104-111` + `Jetty/Stacks/FolderStack.swift:28-44`** · MEDIUM · confidence: high

Drill-in requires `entry.isDirectory && entry.url.pathExtension.isEmpty` — a
heuristic meant to catch bundles (`.app`, `.rtfd`) that also misfires on
ordinary folders like `jquery-3.7.1`, `My.Project`, or `Backups 2024.06`:
clicking them opens Finder and closes the stack instead of navigating. The
correct signal is one resource key away.

**Fix:** fetch `.isPackageKey` in `FolderStack.entries(of:)`, carry
`isPackage` on `FolderEntry`, drill in on `isDirectory && !isPackage`.

### FAB-B7. Return ignores a hover-made selection — the visible highlight and the action disagree
**`Jetty/Menu/JettyMenuView.swift:185-190` + `Jetty/Menu/JettyMenuModel.swift:116-137`** · MEDIUM · confidence: high

Arrow-key selection sets `userMovedSelection`, so Return respects it — but
hover-selection assigns `model.selectedIndex` directly and doesn't. Type
`appe` (matches the *appearance* command keyword **and** "App Store"), hover
App Store — the highlight visibly moves — press Return: **dark mode toggles**
instead of launching the highlighted app. A pointer hover is exactly as
explicit a gesture as an arrow key.

**Fix:** route hover-selection through the model and set
`userMovedSelection = true` there.

### FAB-B8. Tiny non-zero results render as `0` / `-0` — and the copy affordance copies the wrong answer
**`Jetty/Menu/ExpressionEvaluator.swift:179-187` + `Jetty/Menu/UnitConverter.swift:40-46`** · MEDIUM · confidence: high

Formatting goes through fixed-precision `%f` and trims zeros, so any result
below the decimal budget collapses to `"0"`: `10^-11` → **0**; `2^-40` →
**0**; `0-0.00000000001` → **-0**. UnitConverter's 4-decimal budget is worse:
`1 mm to km` → **"0 km"**, `5 mg to kg` → **"0 kg"**. Clicking the row copies
the literal `0` — a wrong answer presented confidently.

**Fix:** when `value != 0 && |value| < 10^-fractionDigits`, fall back to
significant-digits/scientific formatting; never render exactly `"0"`/`"-0"`
for a non-zero result.

### FAB-B9. Pasting pathological input into the menu stack-overflows the app
**`Jetty/Menu/ExpressionEvaluator.swift:131-137,157-172`** · MEDIUM (crash, pathological input) · confidence: high on mechanism

`parseFactor` recurses per leading `+`/`-` and each `(` costs ~5 frames; the
evaluator runs on the main thread on **every keystroke/paste**. Pasting ~100k
`-` or `(` characters (recursion happens *before* the unbalanced-paren check
fails) blows the stack and takes the whole dock down from a launcher text
field — despite the doc comment's "crash-proof on malformed input" claim.

**Fix:** a depth counter in the parser (fail at ~64), convert the unary chain
to a loop, and bail in `evaluate()` for inputs longer than ~256 characters.

### FAB-B10. `X ± Y%` uses ×0.01 semantics instead of percent-of-left-operand
**`Jetty/Menu/ExpressionEvaluator.swift:148-155`** · MEDIUM · confidence: medium-high

`899 - 15%` evaluates to `898.85`, not `764.15`. Every desk calculator,
Spotlight, and Google treat `X ± Y%` as `X ± (Y % of X)`; the ×0.01 reading is
conventional only for `*`/`/` (whose behavior stays unchanged either way).
Users checking a discount get an answer wrong by their expectation, in a
banner styled as authoritative.

**Fix:** for `+`/`-` where the right term is a bare percent postfix, scale by
the accumulated left value.

### FAB-B11. App search breaks for capital-I names under Turkish/Azerbaijani locales
**`Jetty/Menu/AppSearch.swift:40-43`** · LOW · confidence: high

`fold` passes `locale: .current`; under `tr`/`az`, `I` case-folds to dotless
`ı`, so "IINA" becomes unfindable by the query `iina`. Search folding should
be locale-neutral. **Fix:** fold with `locale: nil`.

### FAB-B12. Offline currency queries silently fall through to a Google search of the query
**`Jetty/Menu/JettyMenuModel.swift:78-85` + `Jetty/Menu/CurrencyService.swift:18-36`** · LOW-MEDIUM · confidence: high

When the rates fetch fails (offline / API down), `computeCurrency()` returns
nil with no banner, and Return falls through to web search — so
`100 usd to eur` is shipped to Google, the exact leak class H2 closed for the
online case. **Fix:** when the query *parses* as currency but rates are
unavailable, show a "rates unavailable" banner state that owns Return.

### FAB-B13. Hiding the "24-hour time" toggle for analog faces strands the World Clock
**`Jetty/Settings/WidgetsView.swift:35-37` + `Jetty/Widgets/WorldClockWidgetView.swift:22`** · MEDIUM · confidence: high

The toggle renders only for digit faces, but `WorldClockWidgetView` always
formats with `clockUse24Hour` — and the World Clock caption still says "the
12/24-hour and seconds options above apply here too" while the toggle it
points at has vanished. Pick an analog face and the world clock is stuck in
whatever mode was last set, with no control anywhere in the app.
**Fix:** show the toggle unconditionally.

### FAB-B14. "Add a Link" misparses `host:port` as a URL scheme
**`Jetty/Settings/ItemsView.swift:220-222`** · LOW · confidence: high

The scheme regex matches `localhost:3000` ("localhost" parses as a scheme), so
no `https://` is prepended and the pinned tile is dead on click. Developers
pinning a dev server is a real case. **Fix:** require `//` after the scheme
(or whitelist non-hierarchical schemes like `mailto:`/`tel:`); if what
follows the colon is all digits, treat it as a port.

### FAB-B15. `ColorHex` accepts a signed hex string
**`Jetty/Model/ColorHex.swift:12-15`** · LOW · confidence: high

`UInt64(_, radix: 16)` accepts a leading `+`, so `"+ABCDE"` (length 6) parses
as the 5-digit value `0xABCDE` and decodes as RRGGBB — `validHex` admits
malformed input from hand-edited presets instead of falling back.
**Fix:** pre-validate with `allSatisfy(\.isHexDigit)`.

### FAB-B16. Re-saving a newer document downgrades its content but keeps its `version` stamp
**`Jetty/Model/DockDocument.swift:31` + `Jetty/Store/DockStore.swift:153-172`** · LOW · confidence: high

The tolerant decoder keeps the file's `version`; `saveNow()` re-encodes
verbatim. Run today's build against a future `version: 2` file and the first
debounced save rewrites v1-shaped content still labeled `version: 2`; the
`.bak` of the real v2 file survives exactly one save cycle, and a future build
trusting the stamp skips its migration. **Fix:** stamp
`version = currentVersion` in `saveNow()`; consider load-read-only when
`document.version > currentVersion`.

### FAB-B17. MediaRemote bridge breaks its own "completion on the main queue" contract on early-exit paths
**`Jetty/MediaRemote/MediaRemoteBridge.m:78-79,93,142` vs `MediaRemoteBridge.h:18-19`** · LOW (latent) · confidence: high

Every failure path (`dlopen`/`dlsym` miss, missing classes, setup exception)
invokes `completion` synchronously on the caller's thread; the header promises
main-queue, and `NowPlayingService` mutates `@Published` state in the callback
relying on it. Benign today (only caller is main-thread); the first
background-queue caller — e.g. the H7 fix REVIEW recommends — gets off-main
`@Published` mutations with no diagnostic. **Fix:** wrap the three early
`completion(nil)` calls in `dispatch_async(main)`.

### FAB-B18. Thumbnails-mode window peek hammers a *denied* ScreenCaptureKit query every second
**`Jetty/Windows/WindowPeek.swift:41-59`** · MEDIUM · confidence: high

`canCapture = CGPreflightScreenCaptureAccess()` is computed but never gates
capture: with previews enabled and permission denied, every 1 s tick makes a
full window-server XPC round-trip that just throws, for as long as the peek is
open — the unpermissioned sibling of H20, plus TCC log churn and (macOS 15+)
re-authorization nags. `canCapture` is also never refreshed, so granting
permission mid-peek does nothing until re-hover. **Fix:** gate `refresh()` on
the preflight and recompute `canCapture` per tick.

### FAB-B19. Weather: "tap to retry" tooltip lies, and a transient failure sticks for 15 minutes
**`Jetty/Widgets/WeatherWidgetView.swift:62` + `Jetty/Dock/DockController.swift:430-431` + `Jetty/Widgets/WeatherService.swift:42-55`** · LOW-MEDIUM · confidence: high

The offline glyph's `.help` promises retry, but a tap opens the Weather app;
nothing re-fetches until the next 900 s tick. Wi-Fi comes back and "—" stays
up for 15 minutes. **Fix:** on tap while offline, refresh (matching the
tooltip) instead of/before opening the app; back off to ~60 s retries after a
failure. (Nit: the view nests two `.help` modifiers — offline and default —
whose precedence is undefined; collapse to one computed string.)

### FAB-B20. Recording a hotkey can't capture combos Jetty already owns — the action fires instead
**`Jetty/Settings/HotkeyRecorder.swift:65-83` + `Jetty/Dock/DockController.swift:617-633`** · MEDIUM · confidence: high on design, *needs-device-verify*

Carbon hotkeys stay registered while the recorder is capturing, and they
consume matching events system-wide — so pressing ⌃⌥⌘Space into the "Toggle
the dock" recorder pops the Jetty Menu over Settings instead of recording.
This is why shortcut-recorder libraries pause global registration during
capture. Also: `registerHotkeys()` ignores `register()`'s Bool, and nothing
prevents assigning the same combo to both rows (one registration silently
fails). **Fix:** unregister during recording, re-register after; reject a
candidate equal to the other binding; surface failed registration in the row.

### FAB-B21. `BookmarkResolver` resolves with empty options — hover can trigger a network mount on the main thread
**`Jetty/Store/BookmarkResolver.swift:20`** · MEDIUM · confidence: medium, *needs-device-verify*

Resolution omits `.withoutUI`/`.withoutMounting`, and it runs synchronously on
the main thread in click *and hover* paths (F-P2 flags the sync cost; the
worst case is not a stat but a multi-second mount attempt with UI). Pin a
folder from an office NAS, hover it at home: the dock beachballs while macOS
retries the mount. **Fix:** resolve with `[.withoutUI, .withoutMounting]` for
hover/display; permit mounting only on explicit click, off-main.

### FAB-B22. `DisplayRegistry` collision suffixes are order-dependent
**`Jetty/Screens/DisplayRegistry.swift:38-42`** · LOW · confidence: medium

When two screens report the same hardware UUID (the code's own comment says it
happens), whichever enumerates first gets the bare key — and enumeration order
changes with primary-display changes and reconnect order, so the two displays'
anchors/overrides/disabled flags can swap physical panels across sessions.
**Fix:** order colliding screens deterministically (by `CGDirectDisplayID` or
frame origin) before suffixing.

---

## Performance

### FAB-P1. Analog faces without a visible second hand repaint the whole dial every second
**`Jetty/Widgets/ClockWidgetView.swift:23-26`** · MEDIUM · confidence: high

`showsSeconds = clockShowSeconds || face.isAnalog` forces a 1 Hz TimelineView
for every analog face. With seconds off, the only motion is a sub-pixel
minute-hand creep (≈0.03 pt/tick at the tip) — and **Color Time has no hands
at all** (its wedge moves 0.5°/minute) yet repaints per second. Each tick
redraws all dial furniture: Clock Face 2000 alone builds ~72 `Path`
allocations per frame (60 minute ticks + 12 batons); retro Mac redraws bezel
gradient + 12 studs + the rainbow chip — per second, per display, ~95 % of the
time while hidden (compounding known M4). **Fix:** tick at 1 Hz only when a
second hand is actually drawn; use the minute-aligned 60 s schedule otherwise
(a minute hand stepping 6°/min is *more* in character for a station clock).
Follow-up: render static dial furniture once and keep only hands in the
per-tick layer (FAB-D2).

### FAB-P2. Per-second clock ticks aren't phase-aligned to real seconds
**`Jetty/Widgets/ClockWidgetView.swift:25` + `Jetty/Widgets/WorldClockWidgetView.swift:17`** · LOW · confidence: high

`.periodic(from: .now, by: 1)` anchors at an arbitrary sub-second phase: if
the anchor lands at :xx.7, the LCD/second hand shows second *s* for
[s.7, s+1.7) — stale 70 % of every second, and two clock tiles visibly tick
out of sync with each other and the menu-bar clock. This is the M29 rationale,
fixed for minutes but not seconds. **Fix:** anchor at
`ClockFormatter.minuteStart()` (minute starts are second boundaries).

### FAB-P3. Trash events trigger a full model rebuild + relayout per event, and `trashIcon()` lists the whole Trash each time
**`Jetty/Dock/DockController.swift:72-77` + `Jetty/Dock/DockModel.swift:208-216`** · MEDIUM · confidence: high

Every coalesced `.write` on `~/.Trash` runs the full `rebuildModel()` (the M1
cost) + `relayoutPanels()` (the M3 cost), and each pass materializes
`contentsOfDirectory` for the entire Trash just to compute `isEmpty` —
dragging a few hundred files streams this pipeline for the duration.
**Fix:** debounce `onChange` (~300 ms), test emptiness with a shallow
enumerator/first-element check, and skip the rebuild when the empty/full state
didn't flip — the icon is the only thing that changes.

### FAB-P4. `AppSearch` re-folds the query and per-character-folds every candidate on every keystroke
**`Jetty/Menu/AppSearch.swift:49-66`** · MEDIUM-LOW · confidence: high

Per keystroke, `score` calls `fold(query)` per candidate and builds
`cand.map { fold(String($0)) }` — one `String` allocation + ICU folding per
character of every app name (~300 apps × ~15 chars ≈ 5,000 ICU calls per key,
main thread), despite L6's "fold the query once". Names only change on
`AppIndex.reload()`. **Fix:** precompute folded name + folded char array on
the item at scan time; fold the query once in `rank`.

### FAB-P5. Scope style computes and auto-scales the network series even when network is hidden
**`Jetty/Widgets/SystemMonitorWidgetView.swift:36-48`** · LOW · confidence: high

`scopeBody` maps + `autoScaled`s 60 samples unconditionally; the view only
draws them `if showNetwork`. Two array allocations per 2 s tick per display
for nothing. **Fix:** `showNetwork ? autoScaled(...) : []`.

### FAB-P6. `AppIndex.scan` re-probes every app bundle's Info.plist on every menu open
**`Jetty/Menu/AppIndex.swift:51-63`** · LOW · confidence: high

Hundreds of `Bundle(url:)` constructions + plist reads per open, off-main but
~99 % of opens see zero changes. **Fix:** short-circuit on directory
`contentModificationDate`s, or diff URL sets and probe only new paths.

---

## Visual & layout

### FAB-V1. The zoomed LCD face loses its designed aspect ratio — square at 150 %, portrait at 250 %
**`Jetty/Widgets/ClockWidgetView.swift:38` + `Jetty/Screens/DockLayout.swift:80-82` + `Jetty/Widgets/LCDClockFace.swift:21-22`** · MEDIUM · confidence: high (verified by arithmetic)

`clockTileWidthFactor(zoom:)` budgets width for the **analog** face
(`0.92z + 0.08`), but the LCD wants a 1.35:1 landscape case. At zoom 1 the
1.6× resting width covers it; at zoom 1.5 the box is 1.6h × 1.5h → case aspect
≈ 1.07 (square); at 2.5 it's 2.38h × 2.5h → **0.95, taller than wide**. The
resin sports watch reads as a distorted blob the moment the user zooms, and
the digits shrink relative to the case. **Fix:** make the width factor
face-aware (for `.lcd`, budget `≈1.35·zoom` + slack) — threading the face
through `clockTileWidthFactor`/`tileExtent`/`tileWidth`/`ClockWidgetView`;
`clockZoomHeadroom` already budgets the across-axis correctly.

### FAB-V2. The revealed panel's transparent headroom swallows clicks aimed at windows behind it
**`Jetty/Dock/DockPanelController.swift:409-414` + `Jetty/Dock/DockView.swift:50`** · MEDIUM (HIGH for auto-hide-off + zoomed clock) · confidence: medium-high, *needs-device-verify*

`ignoresMouseEvents` is only true while hidden; while revealed, the whole
window frame — including magnification/zoom headroom — receives clicks, and
`DockView`'s `.contentShape(Rectangle())` makes the entire hosting view
hit-testable. At defaults that's a 26 pt dead band above the glass; with icon
52, zoom 2.5, magnification 1.5 it is **~136 pt tall across the dock's full
width, at `.popUpMenu` level** — permanent for auto-hide-off users.
**Fix:** override `hitTest` to return nil outside the strip band + currently
magnified tile rects, or split the strip into its own child window.

### FAB-V3. Most of a zoomed watch face is click-dead and hover-dead — and hovering up the face cancels its own magnification
**`Jetty/Dock/DockTileView.swift:29-64` + `Jetty/Widgets/ClockWidgetView.swift:63-77` + `Jetty/Dock/DockView.swift:254`** · MEDIUM · confidence: high on hit-testing, *needs-device-verify* on feel

The zoomed face renders as overflow outside the tile's `baseSize`-tall frame,
but `.contentShape(Rectangle())` + tap/hover/context-menu all hit-test the
frame only: on a 250 % face the upper ~60 % of the most prominent pixels in
the dock does nothing on click (and per FAB-V2 the click is swallowed rather
than passed through), while `.help("Open Calendar")` advertises a click that
doesn't work there. Moving the pointer up the face exits the slot stack's
hover bounds, so the face shrinks back out from under the cursor.
**Fix:** for the clock kind, extend the hit shape to the face rect and include
that region in hover tracking.

### FAB-V4. The resting glass strip now carries large empty end-margins (widest-tile headroom rendered as glass)
**`Jetty/Dock/DockView.swift:146-153` + `Jetty/Dock/DockPanelController.swift:330-337`** · MEDIUM · confidence: medium, *needs-device-verify*

`glassStrip` fills the entire panel (`maxWidth: .infinity`), and the panel now
budgets along-axis headroom × `widestTileFactor` (up to 2.4). With icon 52,
magnification 2.0, and a now-playing tile, the resting strip is ~62 pt of
empty glass on *each* end (vs ~13 pt before the zoom commits) — even when the
wide tile sits mid-dock, since the budget assumes it could be at an end.
**Fix:** budget per-end from the actual end tiles' factors (still pure +
testable), or size the visible strip to the tile row and let magnified end
tiles overhang transparently.

### FAB-V5. Bars style still renders its numerals in the raw tint with no plate
**`Jetty/Widgets/SystemMonitorWidgetView.swift:85-98`** · LOW · confidence: medium-high

The 2026-07-02 readability fix (dark plate + `whiteLift`) went to the graph
style only; bars still draw percent text in `barColor(...)` = raw tint below
60 % load, floating on the dock glass — reproducing exactly the bug the graph
fix closed. **Fix:** run the sub-60 % color through `readableCPUColor`.

### FAB-V6. Classic & jelly faces skip the tint-readability guard the monitor got
**`Jetty/Widgets/AnalogClockFace.swift:76-80,284-323`** · LOW-MEDIUM · confidence: medium, *needs-device-verify*

Classic draws its second hand + hub in raw `tint` on a dark dial (near-black
tints — a common theme — make them invisible); jelly fills the dial with
`tint.opacity(0.30)` and draws white hands on it (pale tints wash them out),
and its fixed magenta second hand vanishes on pink tints. **Fix:** run the
tint through the same `whiteLift` blend; give jelly's hands the thin dark
outline Memphis already has.

### FAB-V7. LED meter shows dead columns at idle; sub-1 KB/s reads as a hard `0`
**`Jetty/Widgets/SystemMonitorWidgetView.swift:263-266,286-291`** · LOW · confidence: high

`litSegments` rounds, so anything below 6.25 % lights nothing — an idle
machine shows two dark columns, which on a hi-fi meter reads as "broken", and
`formatRate` renders anything under 1024 B/s as `0`. **Fix:** light the bottom
segment for any value > 0; show `<1K` below 1 KiB/s.

### FAB-V8. CRT overlay still draws at intensity 0
**`Jetty/Common/CRTScreenOverlay.swift:9,18,27`** · LOW · confidence: high

`lineOpacity = 0.08 + 0.30·intensity` has a non-zero floor, so the slider's
minimum still shows scanlines + vignette. **Fix:** scale the floors away so
the slider bottoms out invisible (the toggle stays the hard off).

### FAB-V9. Color Time's hub mini-wheel is likely rotated 90° from the hour ring
**`Jetty/Widgets/AnalogClockFace.swift:363-367`** · LOW · confidence: low, *needs-device-verify*

The hour ring puts `hourColor(0)` at 12 o'clock; the hub's `.conicGradient`
uses the default start angle (3 o'clock) — a 90° mismatch with the dial it
echoes. **Fix:** pass `angle: .degrees(-90)` (verify direction on device).

### FAB-V10. Gauges' needles teleport every 2 s — the "swinging" the style promises never happens
**`Jetty/Widgets/SystemMonitorGaugeView.swift:36-44`** · LOW · confidence: medium-high, *needs-device-verify*

Canvas contents don't implicitly animate, so needles snap on each sample.
**Fix:** draw the needle as an overlaid `rotationEffect` view with a spring
`.animation(value:)`, or make the shape `Animatable`. (Same treatment would
let LED columns rise/fall a segment at a time.)

### FAB-V11. Peek popover's fixed 200 pt height can clip the Screen-Recording hint
**`Jetty/Windows/WindowPeekController.swift:120-126`** · LOW · confidence: medium, *needs-device-verify*

The content stack sums to ~205+ pt when the `!canCapture` hint is shown — the
clipped element is exactly the label explaining how to enable previews.
**Fix:** +24 pt when the hint is visible, or size from `fittingSize`.

---

## UX & interface

### FAB-U1. Auto-hide races the hover popovers — the dock can slide away under an open peek/stack/context menu
**`Jetty/Dock/DockPanelController.swift:224-230` + `Jetty/Dock/DockController.swift:291-327`** · MEDIUM · confidence: medium, *needs-device-verify*

Nothing couples hide scheduling to an open window-peek, folder stack, or
right-click menu: the pointer traveling from tile into popover exits the
keep-revealed region and `scheduleHide()` fires — the dock slides out from
under the popover the user is using, leaving it floating detached.
**Fix:** suppress `scheduleHide` while `windowPeek.isOpen || folderStack.isOpen
|| contextMenuOpen`, or extend the keep-revealed region with the popover frame.

### FAB-U2. Dock-path "Empty Trash?" alert steals activation and never hands it back
**`Jetty/Dock/DockController.swift:588-597`** · LOW-MEDIUM · confidence: high

`confirmAndEmptyTrash()` calls `NSApp.activate(ignoringOtherApps: true)` +
`runModal()` with no capture/restore — the only place in the dock's core path
that violates the never-steal-focus discipline; after dismissing, the user's
app is deactivated with an LSUIElement "frontmost" (the M19 no-menu-bar limbo,
reachable from a plain right-click). **Fix:** capture the frontmost app before
activating and re-activate it after (Finder fallback), mirroring
`JettyMenuController`'s hand-off.

### FAB-U3. "Show seconds" is a silent no-op for Color Time
**`Jetty/Settings/WidgetsView.swift:38`** · LOW · confidence: high

Color Time has no hands; the toggle stays enabled and does nothing.
**Fix:** hide/disable it for faces without a seconds affordance (pairs with
FAB-P1's cadence gating).

### FAB-U4. Animation slider is disabled when auto-hide is off — but it still governs the hotkey toggle slide
**`Jetty/Settings/GeneralView.swift:66-71`** · LOW · confidence: high

`toggleAllDocks()` animates through `animationMs` regardless of `autoHide`;
the row is greyed exactly for the users who toggle by hotkey. **Fix:** don't
disable the row.

### FAB-U5. Adding an already-pinned app is silently ignored
**`Jetty/Settings/ItemsView.swift:176-183`** · LOW · confidence: high

The duplicate guard `continue`s with no feedback — no row, no highlight, no
beep; Add looks broken. **Fix:** select/scroll to the existing row, or beep +
transient caption.

### FAB-U6. Minimize buttons render as functional without Accessibility trust but silently no-op
**`Jetty/Windows/AppWindows.swift:102-105` + `Jetty/Windows/WindowPeek.swift:127-165`** · LOW · confidence: high

`WindowActions.minimize` guards on `AXIsProcessTrusted()` and returns
silently; the ⊖ buttons always render. **Fix:** pass an `axTrusted` flag into
the view; hide the buttons or add an explanatory footer.

### FAB-U7. Log Out / Restart / Shut Down likely confirm twice
**`Jetty/Menu/PowerCommands.swift:53-57` + `Jetty/Menu/JettyMenuController.swift:112-121`** · LOW · confidence: medium, *needs-device-verify*

`tell application "System Events" to restart` triggers the system's own
confirmation dialog; Jetty shows its own `NSAlert` first. **Fix:** skip
Jetty's alert where the OS confirms anyway, or use the no-confirmation
AppleEvent forms and keep Jetty's alert as the single gate.

### FAB-U8. Keyboard scrolling can fight hover-selection when the pointer rests over the menu list
**`Jetty/Menu/JettyMenuView.swift:185-199`** · MEDIUM · confidence: medium, *needs-device-verify*

Arrow-key `scrollTo` slides rows under a stationary cursor; tracking areas
fire `mouseEntered` on view movement, snapping `selectedIndex` back to the row
under the pointer — arrow-down appears to stick. Alfred/Raycast ignore hover
until the pointer physically moves. **Fix:** ignore hover events whose
`NSEvent.mouseLocation` hasn't changed since the last one.

### FAB-U9. A cancelled power-command alert can leave the menu open but dead to the keyboard
**`Jetty/Menu/JettyMenuController.swift:112-124,171`** · LOW · confidence: medium, *needs-device-verify*

On Cancel the menu stays up, but the alert took key status and nothing
re-asserts `panel.makeKey()`; the key monitor's `isKeyWindow` guard then makes
Esc/arrows/typing dead. Reopen-focus similarly depends on AppKit restoring the
first responder (`searchFocused` is only set in `onAppear`).
**Fix:** `makeKeyAndOrderFront` after a cancelled alert; signal focus from
`show()`.

### FAB-U10. `webSearchQuery` trims spaces but not newlines
**`Jetty/Menu/JettyMenuModel.swift:88-91`** · LOW · confidence: high

A pasted trailing newline survives into the row text and the Google query
(`%0A`); a query of only a newline shows a search row for a visually empty
field. **Fix:** trim `.whitespacesAndNewlines`, matching
`ExpressionEvaluator.evaluate`.

### FAB-U11. Drag-to-reorder is likely unusable in the overflow-scroll state
**`Jetty/Dock/DockView.swift:82-90,317-330`** · LOW · confidence: low-medium, *needs-device-verify*

The along-axis `DragGesture(minimumDistance: 10)` competes with `ScrollView`'s
pan, which normally wins. **Fix (if verified):** long-press-then-drag
(`LongPressGesture().sequenced(before: DragGesture())`), or context-menu
"Move left/right" in overflow.

---

## Security & privacy

### FAB-S1. Updater downloads carry no quarantine attribute — the replacement app bypasses Gatekeeper entirely
**`Jetty/Updates/UpdateDownloader.swift:10-20` + `project.pbxproj` (no `LSFileQuarantineEnabled`)** · MEDIUM (complements C1/C2) · confidence: high

Jetty doesn't set `LSFileQuarantineEnabled` and moves the raw download into
`~/Downloads`: files downloaded by a non-quarantining app get **no**
`com.apple.quarantine` xattr, so the downloaded DMG's app is never assessed by
Gatekeeper — no notarization check, no prompt. C1/C2 cover missing in-app
verification and unsigned releases; this is a third, independent gap that
persists even after C2 ships notarized builds. **Fix:** set
`INFOPLIST_KEY_LSFileQuarantineEnabled = YES` (defense in depth — keep it
after C1 lands).

### FAB-S2. A corrupt DMG can ship: `create-dmg … || true` + existence-only check
**`.github/workflows/release.yml:74-82`** · MEDIUM · confidence: high

The `|| true` (justified by create-dmg's spurious exits) masks *all* failures
and the only validation is `[ -f "$DMG" ]` — a truncated image passes and
becomes the release's preferred asset, which the in-app updater hands to every
user with no checksum downstream (C1). **Fix:** `hdiutil verify "$DMG"` after
the existence check. (Related: `create-dmg`/`xcbeautify` install unpinned from
Homebrew at release time — same supply-chain family as C3, distinct channel.)

### FAB-S3. Release-gate test step has no failure diagnostics
**`.github/workflows/release.yml:41-47`** · LOW · confidence: high

CI uploads `TestResults.xcresult` on failure; the release workflow's test gate
doesn't — when a tag's tests fail (the moment you most need to know why), you
get only the xcbeautify stream. **Fix:** mirror ci.yml's result bundle +
`upload-artifact` on failure.

### FAB-S4. `UpdateDownloader` leaves the temp file behind on a non-2xx response
**`Jetty/Updates/UpdateDownloader.swift:11-14`** · LOW · confidence: high

A DMG-sized error body is abandoned in the temp dir. **Fix:** remove
`tempURL` before throwing.

---

## Accessibility

### FAB-A1. Every interactive Jetty Menu row except the power buttons is invisible to VoiceOver
**`Jetty/Menu/JettyMenuView.swift:88-144,203-217`** · MEDIUM · confidence: high

Calc banner, copy rows, command row, web-search row, and all result rows are
plain `HStack`s with `.onTapGesture` — no `.isButton` trait, no combined
element, no default action, no `.isSelected` on the highlighted row, unlabeled
28 pt icons. A VoiceOver user can read fragments but cannot launch an app or
copy a result. (M16/M20/M21 cover the power row, dock tiles, and Settings —
not these rows.) **Fix:** per row,
`.accessibilityElement(children: .combine)` + `.isButton`/`.isSelected` traits
+ `.accessibilityAction`; label copy rows "Copy result: …".

### FAB-A2. LED and Gauges styles drop even the visible numbers
**`Jetty/Widgets/SystemMonitorLEDView.swift:33-48` + `SystemMonitorGaugeView.swift:35-45`** · LOW-MEDIUM · confidence: high

Bars/graph/scope display a numeric percent; LEDs/Gauges show only 6 pt
"CPU"/"RAM" labels (below the 7 pt floor other widgets use) and no value
anywhere — a sighted-parity regression on top of the known M20 VoiceOver gap.
**Fix:** live values in `.help` ("CPU 42 % · RAM 63 %"); raise the label floor
to 7; wire `accessibilityValue` when M20 lands.

---

## Tests, CI & docs

### FAB-T1. `PreferencesTests` leaks a persistent defaults domain per test run
**`JettyTests/PreferencesTests.swift:6-11`** · LOW · confidence: high

`freshDefaults()` removes the suite *before* the test but never after — ~10
orphaned `JettyTests-<UUID>.plist` files accumulate per run on a dev machine,
forever. **Fix:** `addTeardownBlock { removePersistentDomain }`.

### FAB-T2. Highest-value missing tests
Confidence: high · in rough value order:

1. **`SystemMonitorGraph.linePath`/`areaPath`** — the only pure functions in
   the new monitor code with zero coverage (clamping, y-inversion, degenerate
   inputs, baseline closure); they draw every frame of the graph/scope styles.
2. **`DockLayout.pointerCrossedEdge` `.left` branch** — the other three edges
   are tested; four-way switches are the classic copy-paste failure mode.
3. **`Preferences.effectiveClockZoom`** — the one-line gate that turns the
   whole zoom pipeline on/off; untested.
4. **`ClockGeometry.handAngles` with nonzero seconds** — the second-driven
   minute-hand sweep is never exercised.
5. **`PomodoroTimer` resume-after-sleep / persistence** — only `format` is
   tested.
6. **`SystemMonitorStyle.supportsNetwork`** — trivially cheap; silently
   controls whether the network toggle does anything.
7. *(known, re-endorsed: F-R9 `.bak` rotation; F-R6 hermetic downloader
   tests)*

### FAB-T3. `PLAN.md` §11's project tree is significantly stale — and `AGENTS.md` leans on it
**`PLAN.md:511-607` + `AGENTS.md:66-96`** · LOW · confidence: high

The tree omits three shipped modules (`Stacks/`, `MediaRemote/`, `Windows/`)
and dozens of real files, and lists three test files that don't exist.
`AGENTS.md`'s Module Layout omits `Windows/` and `TrashMonitor` while its own
constraints reference them. `PLAN.md` also says corner radius "0–32" where
code/UI say 0–40. **Fix:** regenerate the tree from the filesystem; add the
`Windows/` bullet + `TrashMonitor` to AGENTS.md; fix the range.

### Small nits (bundled)
- **`WidgetsView.swift:87`** — the weather example "−122.42" uses U+2212
  MINUS, which the `.number` TextField won't parse if pasted; use ASCII `-`
  (and locale-aware examples).
- **`AppearanceView.swift:114-127`** — exported presets are always named
  "My Theme" (the name param is never passed) and the write is non-atomic;
  export errors surface through a variable named `importError`.
- **`Jetty/Dock/DockContextAction.swift:13`** — all separators share one
  static `UUID`; a future menu with two separators gets duplicate
  `Identifiable` ids. (Interacts with known L34: fixing L34 via `id: \.title`
  would make this worse — use positional/stable ids for both.)
- **`SystemMonitorWidgetView.swift:253-255`** — `whiteLift` is a hard step at
  luminance 0.35; a ramp would avoid very different renders for 0.34 vs 0.36
  tints.

---

## Verified clean

Recorded so the next review doesn't re-litigate:

- **The face-zoom math is exact.** `clockZoomHeadroom` (panel across =
  `padding + icon·(zoom+0.04)·mag`) matches the scaled face top for both LCD
  and analog; `clockTileWidthFactor`'s crossover (zoom ≈ 1.652) correctly
  keeps the face inside the resting 1.6× tile; the hand-computed values in
  `DockLayoutTests` (23.28 / 97.12 / 2.38) all check out. The drift bugs above
  are in the *integration seams*, not the formulas.
- Vertical docks are consistently gated across the zoom pipeline; the layout
  preference signature correctly includes `clockFace` + `clockFaceZoom`
  (live resize works); `effectiveClockZoom`'s digital→1× gate is used
  consistently in all the places that matter.
- The `clockAnalog → ClockFaceStyle` migration is correct and unit-tested
  (stored face wins; `"swiss"` maps to Clock Face 2000).
- The web-search encoding fix (commit `34f977b`) is **correct**: `c++`,
  `AT&T`, `a=b`, `100%`, unicode, and emoji all encode properly; the post-hoc
  `+` → `%2B` on `percentEncodedQuery` is safe and targeted.
- `ClockFaceTests` / `InfoWidgetTests` / `SevenSegment` / `ClockGeometry`
  expected values verified by independent arithmetic — all correct.
  `CommandBarTests` are hermetic (CurrencyService never fetches on init).
- Preset import hardening (angle normalization, `validHex`, tolerant enums,
  Zap-preset sniffing) is solid; `DockStore`'s `.bak` rotation and the lossy
  `Failable` decode behave as documented; `CarbonHotkey`'s failed-registration
  rollback is correct.
- README/AGENTS claims spot-checked true: default shortcuts, settings labels,
  face roster, monitor styles, `dock.json` path, version markers (README
  v1.0.1 == `MARKETING_VERSION` in all four configurations).

---

## Endorsed backlog

Existing `REVIEW.md` items I looked at again and am implementing now because
they're well-specified, low-risk, and high-value (see the
[implementation plan](#implementation-plan)): **F-P4** (equality-gate
`RunningAppsModel.refresh`), **F-M12** (dedup/index representative agreement),
**M12** (real currency formatting), **M19** (nil-restore → Finder fallback),
**M35** (per-command confirmation wording + exhaustive switch), **M36**
(`uniqueDestination` cap + symlink defense), **F-R6** (hermetic downloader
tests), **F-L5** (word-order-insensitive app search), **F-L10** (now-playing
generation token), **F-L11** (TrashMonitor re-arm), **M26** (folder stack:
sort/trim before icon loads), **L9/L10** (ColorHex alpha round-trip + CSS
shorthand), **L17** (world-clock `TimeZone` caching), **L29** (stack back
button hit target), **F-P7** (BoingBall per-scale cache), **F-R9** (`.bak`
rotation tests).

Still important, not implementable from this environment: **C1/C2** (update
verification/signing — needs keys), **C3** (action SHA pinning — needs
network access to resolve real SHAs; pinning to invented SHAs would be worse
than the status quo), **H8** (magnification squish — needs on-device tuning),
and the *needs-device-verify* items above.

---

## Delight — fresh ideas

(REVIEW.md's ideas list still stands; these are new.)

- **FAB-D1. One pure `DockGeometry`.** `tileCenters`, `tileAnchor`, the glow
  lead, and the panel `contentSize` each re-derive the same math — FAB-B2 is
  the *second* mirror-drift bug in this area. One unit-tested
  `DockGeometry(kinds:iconSize:spacing:edge:zoom:magnification:)` with
  `centers`, `lead`, `contentSize` ends the class of bug.
- **FAB-D2. Static-dial cache + hands-only tick layer.** Render dial furniture
  once (keyed by style/size/tint), tick only the hands — cuts per-second
  widget work to 2–3 strokes and enables smooth-sweep options for free.
- **FAB-D3. Install & Relaunch.** Mount/verify in a private temp dir, swap
  `Bundle.main.bundleURL` atomically, relaunch — turns the weakest UX moment
  (manual DMG drag) into one click, and gives the C1 verifier a natural home.
- **FAB-D4. "What's new" after an update.** Persist last-run version; on
  first launch of a newer one, show the already-fetched release notes in a
  small glass panel.
- **FAB-D5. ETag-conditional update checks.** GitHub 304s don't count against
  the rate limit — makes L4 moot for free.
- **FAB-D6. Quick Look + drag-out in folder stacks.** Space/right-click →
  `QLPreviewPanel`; `.onDrag { NSItemProvider(contentsOf:) }` on stack rows so
  files drag straight into Mail/Slack. Native-citizen feel, no permissions.
- **FAB-D7. Per-stack sort control.** Name / Date / Kind in the stack header —
  `FolderStack.orderedBefore` is already the pure seam.
- **FAB-D8. Close button on peek thumbnails.** ⊗ pressing the AX close button
  — same permission as minimize, and something the real Dock can't do.
- **FAB-D9. LED peak-hold.** A per-column max that decays a segment per
  ~1.5 s — the defining hi-fi-meter behavior, ~15 lines, pure helper that
  slots into the tested `SystemMonitorGraph` family.
- **FAB-D10. Date aperture at 3 o'clock** on classic/Clock Face 2000
  (`clockShowDate` currently does nothing on analog faces) — period-correct.
- **FAB-D11. Analog world clock.** `AnalogClockFace` already takes a `date`;
  feed it a zone-shifted one + a city label + a darkened dial between local
  sunset/sunrise.
- **FAB-D12. Blinking LCD colon** (1 Hz, colon layer only, once FAB-D2
  lands) — the definitive 80s idiom.
- **FAB-D13. Scope sweep cursor + gauge over-rev flash.** A slow bright
  phosphor line on the newest sample; a pulsing redline when CPU pins >10 s.
- **FAB-D14. Native dictionary lookup in the menu.** `define serendipity` →
  `DCSCopyTextDefinition` inline banner — offline, zero permissions, perfectly
  on-brand.
- **FAB-D15. "time in tokyo"** in the menu — the world-clock machinery already
  exists; live clock banner, copy = the time string.
- **FAB-D16. Esc clears, then closes.** First Esc empties a non-empty query,
  second closes (Spotlight behavior) — today Esc discards a long-typed query.
- **FAB-D17. Conversion swap key.** With a conversion banner up, ⇥ re-runs it
  reversed (`10 km in mi` ⇄) — cheap, uses the already-parsed query.
- **FAB-D18. Rate provenance chip** on the currency banner ("ECB · 3 h ago",
  stale tint after 24 h) — turns the M31 fetch into visible trust and doubles
  as the offline indicator for FAB-B12.
- **FAB-D19. Implicit multiplication** (`2(3+4)`) — Spotlight parity, a
  one-line juxtaposition rule in `parseTerm`.
- **FAB-D20. Fold widget looks into `AppearancePreset`** (`clockFace`,
  `clockFaceZoom`, `systemMonitorStyle`, `showNetwork`): the retro themes
  become coherent — Amiga → retro Mac face + Scope, Vapor → jelly, ZX Night →
  LCD — and shared themes carry their whole look. (Tolerant decode + clamp per
  the existing accentGlow precedent.)
- **FAB-D21. "Forget this display."** Stored anchors/overrides for unplugged
  monitors are invisible and immortal; list them under "Not connected" with a
  forget button.
- **FAB-D22. Forward-geocode the weather location** (`CLGeocoder`, network
  geocoding, no location permission) — type a city instead of coordinates;
  complements L18's reverse-geocode display.
- **FAB-D23. Transient ⌥-hover face zoom.** Hold Option while hovering the
  clock to zoom the face temporarily — the "glance at the watch" gesture,
  without permanently spending the headroom (or the FAB-V2 click band).
- **FAB-D24. Vertical-dock face zoom via across-axis growth.** The stated
  blocker (along-axis overlap) doesn't apply to growing *inward*; after the
  F-V2 fix, a mirrored `clockZoomHeadroom` on width finishes it.
- **FAB-D25. Overflow zoom hysteresis.** Scale effective zoom continuously as
  free space shrinks (`min(zoom, availableFactor)`) so adding one app never
  snaps the face from 250 % to 100 %.
- **FAB-D26. Animated CRT flicker.** A rolling brighter scanline + ±2 %
  opacity jitter on a slow TimelineView — makes the retro presets feel alive.
- **FAB-D27. Battery time-to-full/empty in the tooltip**
  (`IOPSGetTimeRemainingEstimate` — public, free; the tile's `.help` today
  says just "Battery").
- **FAB-D28. Cross-link Widgets ⇄ Items.** Each widget section shows "This
  tile isn't in your dock — Add" (one `contains(kind:)` check).
- **FAB-D29. Grouped world-clock zone picker.** The flat ~600-row `Picker` is
  nearly unusable; group by region, or curated list + searchable "Other…".
- **FAB-D30. Color Time a11y in its own language.** `.help("About 3
  o'clock")` — the Chromachron's deliberate approximateness becomes a feature
  instead of a mystery dial.

---

## Implementation plan

Entries I'm implementing now, grouped into branches chosen to keep PRs
coherent and minimize cross-PR merge conflicts (same-file entries share a
branch; independent files get their own). Everything not listed stays as
backlog above — mostly *needs-device-verify* items and product decisions.

| Branch | Entries |
|---|---|
| `fable2/second-instance-teardown` | FAB-B1 |
| `fable2/systemdock-guards` | FAB-B4, FAB-B5 |
| `fable2/dock-geometry-mirrors` | FAB-B2, FAB-B3 |
| `fable2/lcd-zoom-aspect` | FAB-V1 (stacked on geometry-mirrors if needed) |
| `fable2/folder-stacks` | FAB-B6, M26, L29 |
| `fable2/menu-fixes` | FAB-B7, FAB-B12, FAB-U10, FAB-A1, M12, M19, FAB-D16 |
| `fable2/expression-evaluator` | FAB-B8, FAB-B9, FAB-B10, FAB-D19 |
| `fable2/app-search` | FAB-B11, FAB-P4, F-L5 |
| `fable2/clock-cadence` | FAB-P1, FAB-P2, FAB-B13, FAB-U3, L17 |
| `fable2/system-monitor-polish` | FAB-V5, FAB-V7, FAB-P5, FAB-A2 |
| `fable2/weather-retry` | FAB-B19 |
| `fable2/trash-pipeline` | FAB-P3, F-L11 |
| `fable2/runningapps-consistency` | F-P4, F-M12 |
| `fable2/nowplaying-robustness` | FAB-B17, F-L10 |
| `fable2/update-downloader` | FAB-S4, M36, F-R6 |
| `fable2/quarantine-flag` | FAB-S1 |
| `fable2/release-workflow` | FAB-S2, FAB-S3 |
| `fable2/colorhex` | FAB-B15, L9, L10 |
| `fable2/power-commands` | M35 |
| `fable2/settings-fixes` | FAB-B14, FAB-U4, FAB-U5, weather-example nit |
| `fable2/windowpeek-preflight` | FAB-B18 |
| `fable2/small-visual-fixes` | FAB-V8, separator-id nit + L34 |
| `fable2/store-version-stamp` | FAB-B16, F-P7 |
| `fable2/test-hardening` | FAB-T1, FAB-T2 (new test files), F-R9 |
| `fable2/docs-truth` | FAB-T3 |

Deliberately **not** implemented from this environment (no compiler, no GUI):
FAB-V2/V3/V4/V6/V9/V10/V11, FAB-U1/U7/U8/U9/U11, FAB-B20/B21/B22, FAB-P6,
FAB-B18's `canCapture` UI half, H8, C1–C3 — each needs on-device verification,
signing keys, or network access this session doesn't have. They're specified
above precisely so a device session can pick them up.

---

*Companion to `REVIEW.md` (the living backlog). Once these branches merge,
fold the still-open FAB-\* items into REVIEW.md the way the earlier reviews
were folded, and let this file retire into history like `GPT-is-awesome.md`
before it.*
