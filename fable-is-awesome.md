# Jetty — the Fable review

A fresh, deep review of `main` (v1.0.1, `571ab6e`) covering bugs, performance,
visual/layout problems, UX gaps, missing features, and new ideas.

**How this relates to `REVIEW.md`:** that file is the previous consolidated
review and remains the record for its own open backlog. This review does three
things on top of it: (1) it reports **new findings the prior review missed** —
the large majority of what follows; (2) it **re-verifies** the prior backlog
items that this review's fixes touch (confirmations are marked); (3) it
**corrects** a few prior-review claims that turn out to be wrong or stale
(see [Corrections to REVIEW.md](#corrections-to-reviewmd)).

**Method & confidence.** The codebase was reviewed module-by-module by
parallel reviewers plus cross-cutting passes, and the load-bearing findings
were then re-verified by hand against the current tree (an adversarial
verification stage was partially cut short by API limits — where a finding
could not be hand-verified, its confidence label says so). Everything cites
current `file:line`. There is no macOS toolchain in this environment, so
nothing here was compile-checked or run; findings that need a live GUI to
confirm are marked **needs-device-verify**.

Severity: **F-C** critical · **F-H** high · **F-M** medium · **F-L** low.
Items marked **[planned: `branch-name`]** are implemented in a matching PR
branch (see [Implementation plan](#implementation-plan)).

---

## Table of contents

- [High-severity bugs](#high-severity-bugs)
- [Medium bugs](#medium-bugs)
- [Low bugs & polish](#low-bugs--polish)
- [Performance](#performance)
- [Visual & layout](#visual--layout)
- [UX & product gaps](#ux--product-gaps)
- [Release engineering, CI, tests & docs](#release-engineering-ci-tests--docs)
- [Corrections to REVIEW.md](#corrections-to-reviewmd)
- [Status of the prior backlog](#status-of-the-prior-backlog)
- [New ideas](#new-ideas)
- [Implementation plan](#implementation-plan)
- [What's genuinely good](#whats-genuinely-good)

---

## High-severity bugs

### F-H1. Turning Auto-hide OFF while the dock is hidden leaves it permanently invisible
`Jetty/Dock/DockPanelController.swift:149,192` + `Jetty/Dock/DockController.swift:150` · **[planned: `fable/autohide-off-reveals`]**

`isRevealed` is only seeded from the preference in `showInitial()`. Unchecking
Auto-hide while the dock is auto-hidden routes through the `layout` signature →
`relayoutPanels()` → `applyRevealState(animated: false)`, which re-applies the
*current* `isRevealed == false`: hidden transform, `ignoresMouseEvents = true`.
From then on `handleMouseMoved` bails on its `guard preferences.autoHide` and
nothing ever calls `reveal()`. The user asked for an always-visible dock and got
a permanently invisible, click-through one; the escape hatches (toggle hotkey,
status-item "Toggle Dock") are not discoverable from the Settings toggle that
caused it. **Fix:** in `applyPreferenceChange()`, when `!preferences.autoHide`,
force-reveal all panels (idempotent — `reveal()` no-ops when already revealed).

### F-H2. Settings "Restore System Dock" is silently undone by the next preference change
`Jetty/Settings/GeneralView.swift:20` vs `Jetty/AppDelegate.swift:153-156` · **[planned: `fable/settings-restore-system-dock`]**

The two identically-named controls diverge: the menu-bar item clears
`preferences.manageSystemDock` before restoring; the Settings button only calls
`systemDock.restoreSystemDock()`. Since `restoreSystemDock()` sets
`isManaging = false` while the preference stays `true`, the very next preference
change hits `applyPreferenceChange()`'s
`if preferences.manageSystemDock { if !systemDock.isManaging { hideSystemDock() } }`
and re-hides the Dock (with a `killall Dock` flash) — e.g. click Restore, then
drag any slider in the same window and the Dock vanishes again. Same on next
launch. README documents this button as *the* restore path. Verified by hand.

### F-H3. "Edge inset" is a visual no-op on bottom/left/right — and can draw Jetty on top of the live system Dock
`Jetty/Dock/DockPanelController.swift:349-363` + `Jetty/Dock/DockView.swift:39-43` · needs-device-verify for the exact rendering, logic verified

`DockLayout.revealedFrame` lifts the frame by `inset`, but `recomputeFrames()`
then stretches the panel back to the physical edge (`frame.origin.y = f.minY;
frame.size.height += dy` — every edge except `.top`), and `DockView` pins the
glass strip to the edge-facing side of the panel. So the strip renders at the
physical screen edge no matter what inset is set: the "Edge inset" sliders
(General + Displays) and the documented "floating island" look do nothing on 3
of 4 edges, contradicting README's "a fine offset and an edge inset, per
display". Worse: when the system Dock is visible (`manageSystemDock` off, or
after Restore while Jetty runs), `dy` equals the Dock's height and Jetty's
strip is stretched down over the live Dock at `.popUpMenu` level. The stretch
only ever fires in those two cases — with the Dock hidden and inset 0, `dy == 0`
— so it currently has no beneficial case on those edges. **Fix:** guard the
stretch to `anchor.inset == 0 && dy <= small`, or keep the stretched panel but
convert the inset into edge-side content padding so hard-edge clicks still land
on icons while the strip floats.

### F-H4. Return runs a matched quick-toggle over the user's arrow-selected app; keyword match can never be escaped
`Jetty/Menu/JettyMenuModel.swift:108-116` + `Jetty/Menu/MenuCommand.swift:43` · **[planned: `fable/menu-return-priority`]**

Two compounding bugs. (1) `activateSelection()` unconditionally prefers a
matched command: type "dark", press ↓ to select the visibly-highlighted
*Darkroom* row, hit Return — your system appearance toggles instead of the app
launching (the BUG-5 fix protected clicks, not keyboard selection).
(2) `MenuCommand.match` uses `$0.hasPrefix(q) || q.hasPrefix($0)`; the second
direction means any query that *starts with* a keyword matches forever —
"darkroom", "darker", "appearance settings" can never launch an app or reach
web search via Return. Also subsumes prior-review **H2**: with a calculation
banner showing, Return should copy the result, not open Google. Verified by
hand.

### F-H5. An imported preset with a huge/non-finite `gradientAngle` bricks the Appearance pane (crash on every visit)
`Jetty/Model/Preferences.swift:227,314` + `Jetty/Settings/AngleDial.swift:46` · **[planned: `fable/preset-hardening`]**

Every numeric in `Preferences.apply(_:)` and `init` is clamped **except**
`gradientAngle`. `AngleDial` renders
`.accessibilityValue("\(Int(angleDegrees.rounded())) degrees")`, and
`Int(Double)` traps outside Int range (and on non-finite values). A shared
theme JSON with `"gradientAngle": 1e300` imports fine, applies, persists to
UserDefaults — and then the Appearance pane crashes the app on every visit
until the default is deleted by hand. Exactly the hardening class M28/H19 did
for hex colors; the angle was missed. Verified by hand.

### F-H6. No single-instance guard — the updater's own flow invites a second running copy
`Jetty/AppDelegate.swift:26` + `Jetty/Updates/UpdateChecker.swift:196` · **[planned: `fable/lifecycle-basics`]**

The updater downloads a new Jetty into `~/Downloads` and reveals it in Finder.
LaunchServices only dedups launches of the *same bundle path*, so double-
clicking the new copy while the old one runs starts a second full instance.
Both instances then fight over the shared `com.apple.dock` defaults and the
shared `SystemDock.isManaging` flag — quitting one restores the system Dock out
from under the other, which then never re-hides it. There is also no
`applicationShouldHandleReopen`, so re-opening the app does nothing visible.
**Fix:** on launch, if another instance with the same bundle id is running,
activate it and terminate; add a reopen handler that surfaces Settings.

### F-H7. A prerelease tag is published as a full "latest" release and pushed to every user by the in-app updater
`.github/workflows/release.yml:5,75` + `Jetty/Updates/GitHubReleaseClient.swift:40` · **[planned: `fable/ci-release-hardening`]**

`release.yml` triggers on `tags: ['v*']` (matches `v1.1.0-beta.1`) and the
`softprops/action-gh-release` step never sets `prerelease:` — so any tag
becomes GitHub's "latest". The updater's default path fetches
`releases/latest` and its `allowPrereleases` gate is silently defeated because
CI never marks anything prerelease; `SemanticVersion` correctly orders
`1.1.0-beta.1 > 1.0.1`, so every stable user is offered the beta. One-line fix:
`prerelease: ${{ contains(github.ref_name, '-') }}`. Verified by hand.

### F-H8 (confirmed open). Pomodoro completes instantly after the Mac sleeps; weather errors leave a spinner forever
`Jetty/Widgets/PomodoroTimer.swift:31,65` · `Jetty/Widgets/WeatherService.swift:54` · prior-review H12/H15 · **[planned: `fable/pomodoro-robustness`, `fable/weather-robustness`]**

Both re-verified unchanged against the current tree. Pomodoro: absolute
`endDate`, no sleep/wake observers, no persistence — closing the lid mid-
session "completes" it on wake. Weather: `dataTask { data, _, _ }` discards the
response and error; a failed first fetch shows an infinite `ProgressView` with
retries only every ~15 min and zero feedback.

---

## Medium bugs

### F-M1. Duplicate pinned tiles break the unique-tile-id invariant DockModel documents as load-bearing
`Jetty/Dock/DockModel.swift:103,130` + `Jetty/Settings/ItemsView.swift:157,36` · **[planned: `fable/unique-tile-ids`]**

Every pinned application tile gets id `"app:\(bundleID)"`, but the dedup guard
that protects the id invariant only covers running-only tiles. `ItemsView.
addApplication` adds unconditionally (picking an already-pinned app duplicates
it; two on-disk copies of one app collide too), and the Add menu happily adds a
**second `.runningApps` sentinel**, which re-emits the *entire running group
twice* (the `emittedRunning` flag only guards the trailing auto-append, not
repeated sentinels). Duplicate ids feed SwiftUI `ForEach` (undefined behavior)
and collide in `tileCenters` — magnification centers on the wrong copy, hover
lights both. Verified by hand.

### F-M2. The menu's local key monitor breaks CJK/IME composition
`Jetty/Menu/JettyMenuController.swift:147-158` · **[planned: `fable/menu-focus-and-keys`]**

The monitor consumes Return/Esc/↑/↓ before the field editor's input context
sees them. With an active IME, Return must commit the conversion and arrows
navigate the candidate window — instead Return launches an app with marked text
still in the field, and Esc closes the whole menu mid-composition. Effectively
unusable for CJK users searching localized app names (which the index
deliberately supports). Fix: pass events through while
`(panel.firstResponder as? NSTextView)?.hasMarkedText() == true`; also guard on
`panel.isKeyWindow` (prior-review M15).

### F-M3. Closing the menu steals focus back from the app the user just clicked
`Jetty/Menu/JettyMenuController.swift:73` · **[planned: `fable/menu-focus-and-keys`]**

`close()` unconditionally re-activates the remembered app. But close is also
triggered by the resign-key observer when the user clicks a *different* app —
that app just became frontmost by explicit user action, and Jetty yanks focus
back to whatever was frontmost at open time (on macOS 13 with
`.activateIgnoringOtherApps`). The same unconditional restore races the
`config.activates = true` launch in the `onLaunch` path. Fix: only restore when
`NSApp.isActive` (dismissal came from Esc/copy/launch, not from focusing another
app); clear the restore target when launching. Prior-review M19 (nil-restore →
Jetty stuck frontmost) is the sibling case, fixed together.

### F-M4. Power commands / dark-mode toggle run AppleScript synchronously on the main thread
`Jetty/Menu/PowerCommands.swift:78-84` + `Jetty/Menu/MenuCommand.swift:48-52` · needs-device-verify

AppleEvent sends block the calling thread (up to the two-minute AE timeout, or
until the first-use TCC consent is answered), and the menu closes *before*
running — so "Empty Trash" grinding through a large Trash freezes the whole
app, dock panels and all, with no visible cause. Fix: run the script on a
dedicated serial queue (NSAppleScript isn't main-thread-bound, just not
concurrency-safe), hop back to main for error surfacing (pairs with
prior-review H21).

### F-M5. Weather: toggling unit/location back within 15 minutes strands the tile on a spinner
`Jetty/Widgets/WeatherService.swift:42-43` · **[planned: `fable/weather-robustness`]**

`refreshIfStale` clears the snapshot (`if snapshot?.key != key { snapshot = nil }`)
*before* the freshness early-return. Flip °C→°F→°C before the °F fetch resolves:
the snapshot for °C was valid and cached, but it's been thrown away, the
freshness gate says "fresh, don't refetch", and the late °F callback is
discarded — spinner until the 15-minute window ages out. Verified by hand: the
view already gates on `snap.key == key`, so the clearing line is unnecessary.

### F-M6. Network rate divides by the nominal 2 s interval — absurd spike after sleep
`Jetty/Widgets/LiveSystemStats.swift:86,109` · **[planned: `fable/sampler-accuracy`]**

Timers don't fire during sleep and coalesce on wake, so the first post-sleep
byte delta covers hours but is divided by 2 s — a 100 MB Power-Nap transfer
renders as a "50 MB/s" spike (the inverse of the H13 wrap-dip). Fix: track the
actual elapsed time between samples; drop the baseline when the gap is large.
Related seam: `startTimer()` resets the network baseline but **not** `history`,
so the sparkline splices pre-gap samples onto post-gap ones as one continuous
2-minute line.

### F-M7. Changing the Pomodoro session length does nothing until a session completes or is reset
`Jetty/Widgets/PomodoroTimer.swift:19,29,52` · **[planned: `fable/pomodoro-robustness`]**

`pomodoroMinutes` is read only in `init` and `reload()`, and `start()` only
reloads when `remaining <= 0`. Change 25 → 50 in Settings, tap the tile: a
25:00 session starts, and the idle tile keeps displaying 25:00 indefinitely.
The class comment ("Duration is read from Preferences at (re)start") is not
honored for the idle-at-full-duration case. Verified by hand.

### F-M8. Preset import isn't tolerant of unknown enum values, contradicting its own comment
`Jetty/Model/AppearancePreset.swift:82,92,117` · **[planned: `fable/preset-hardening`]**

`decode(from:)`'s comment claims the decoder "never fails — defaults fill any
gap", but `decodeIfPresent(DockMaterial.self, …)` **throws** on an unknown raw
value (it only tolerates a missing key). A theme from a future Jetty (or a
typo'd hand-edit) fails the whole import with the misleading "That file isn't a
Jetty or Zap theme." The codebase already has the right pattern
(`(try? c.decodeIfPresent(...)) ?? default` in `DockItem`). Also:
**`accentGlow` is the only Appearance-pane setting missing from the preset**,
so an exported theme silently loses it round-trip.

### F-M9. Weather coordinates from the TextField are persisted unclamped
`Jetty/Settings/WidgetsView.swift:56,62` + `Jetty/Model/Preferences.swift:199` · **[planned: `fable/settings-panes`]**

The lat/long TextFields persist raw values; the −90…90 / −180…180 clamp exists
only in `Preferences.init`. Typing `377.7` (typo for 37.77) is legal all
session (Open-Meteo errors → spinner forever, see F-H8), then silently snaps to
90 on relaunch — a different wrong location.

### F-M10. HotkeyRecorder ignores SwiftUI `.disabled` — the grayed-out recorder still records
`Jetty/Settings/HotkeyRecorder.swift` + `Jetty/Settings/GeneralView.swift:81` · **[planned: `fable/settings-panes`]**

`.disabled` only sets the environment's `isEnabled`; the `NSViewRepresentable`
never forwards it to the wrapped `NSButton`, so the dimmed control still grabs
first responder and rewrites the persisted binding while its toggle is off.
Two-line fix: `nsView.isEnabled = context.environment.isEnabled` in
make/update. Related (needs-device-verify): while recording, Jetty's own Carbon
hotkeys stay registered, so pressing the current combo toggles the dock instead
of being captured; and nothing prevents assigning the identical combo to both
shortcuts.

### F-M11. Tint & background-opacity controls are silent no-ops for the default Liquid Glass / Clear materials
`Jetty/Settings/AppearanceView.swift:18,27` + `Jetty/Common/GlassBackground.swift:44` · **[planned: `fable/settings-panes`]** (caption approach)

`GlassBackground` only consumes `tint`/`opacity` for `.glassTinted` (and the
solid/gradient paths); for `.liquidGlass` (the shipped default) and
`.glassClear`, dragging Background opacity or picking a Tint changes nothing on
screen. The pane already conditions gradient controls on `material == .gradient`
— these two just weren't conditioned.

### F-M12. Tile clicks can target a different process than the tile represents (dedup first-wins vs index last-wins)
`Jetty/Apps/RunningAppsModel.swift:64,72-79` · needs-device-verify for repro, logic certain

The published snapshot dedups duplicate bundle-ids keeping the **first**
instance; `indexByBundle` keeps the **last**. In exactly the dual-instance
scenario the dedup comment itself calls real, the tile renders instance A's
`pid`/`isActive` while clicks, Show/Hide/Quit, and the active glow operate on
instance B — "Quit" can terminate a different process than the tile shows.

### F-M13. Apps that change activation policy at runtime never appear/disappear
`Jetty/Apps/RunningAppsModel.swift:34-50` · needs-device-verify

The model listens to six NSWorkspace notifications; none fires when a running
app flips `activationPolicy` (Electron tray-mode toggles, "Show Dock icon"
preferences). The real Dock updates immediately;
`NSWorkspace.runningApplications` is KVO-observable for exactly this.

### F-M14. Background update check activates Jetty and runs a modal alert — steals focus at login
`Jetty/Updates/UpdateChecker.swift:91,227` · needs-device-verify

`runModal` unconditionally activates the app first, and background checks reach
it — with launch-at-login, the user logs in, starts typing, and Jetty yanks
activation to a modal alert (a stray Return = Download). The only place in the
app that activates without a user gesture, against the project's own
never-steal-focus discipline. Related: the Download path has **zero** UI —
`isDownloading` is published but observed by nothing, and failure silently
opens a browser tab.

### F-M15. The system Dock is hidden on first launch without the consent README promises
`README.md:105` + `Jetty/Model/Preferences.swift:51` + `Jetty/Dock/DockController.swift:59` · **[planned: `fable/docs-truth`]** (wording); consent flow is a product decision

"(with your consent) hides the system Dock" — there is no consent step:
`manageSystemDock` defaults `true` and `start()` rewrites `com.apple.dock`
defaults + `killall Dock` unconditionally on first run. Either add a one-time
first-launch confirmation, or fix the README wording. The doc fix ships now;
the consent alert is recommended as follow-up.

---

## Low bugs & polish

- **F-L1. Calculator: `-2^2` evaluates to 4** (`ExpressionEvaluator.swift:126-143`).
  Unary minus binds tighter than `^`, contradicting Spotlight/Google/Python
  (−4). A silently wrong answer in a copy-to-clipboard calculator is worse than
  none. Verified by hand. **[planned: `fable/calculator-precedence`]**
- **F-L2. Calculator rejects the Unicode minus `−` (U+2212)** — the exact
  character math copied from web pages/PDFs contains; `×`/`÷` are aliased but
  `−` isn't, so pasted expressions silently fall through to web search.
  **[planned: `fable/calculator-precedence`]**
- **F-L3. Web-search sends `+` literally** (`JettyMenuController.swift:117-124`):
  URLComponents leaves `+` unescaped in queries; Google decodes it as a space —
  "c++" searches for "c  ", and the F-H4 calculator fall-through turns "2+2"
  into "2 2". One-line `percentEncodedQuery` fix. **[planned: `fable/menu-focus-and-keys`]**
- **F-L4. App search can't find Finder** (`AppIndex.swift:22-36`): the scan list
  omits `/System/Library/CoreServices` — "Finder", "Screen Sharing", "Archive
  Utility" return nothing, which reads as a broken search. **[planned: `fable/appindex-finder-inflight`]**
- **F-L5. App search is word-order sensitive** (`AppSearch.swift:39-72`):
  "studio visual" finds nothing for Visual Studio Code — the query matches as a
  single ordered subsequence. Spotlight/Alfred tokenize and AND the words.
  (Also still not diacritic-insensitive — prior-review H4, confirmed;
  **[planned: `fable/search-diacritics`]**.)
- **F-L6. Battery `isPlugged` is dead code, and plugged-not-charging renders as on-battery**
  (`SystemStats.swift:16,30`, `BatteryWidgetView.swift:23`): a MacBook held at
  80% by Optimized Charging shows the plain on-battery glyph. Ties into
  prior-review M30 (charging always shows the 100% glyph, no low-battery
  emphasis) — all fixed together. **[planned: `fable/battery-tile`]**
- **F-L7. Clock/world-clock text overflows the fixed 1.6× tile**
  (`ClockWidgetView.swift:36`, `WorldClockWidgetView.swift:25`): 12-hour +
  seconds ("10:00:00 PM") wraps/truncates — no `lineLimit`/`minimumScaleFactor`
  anywhere; worse at small icon sizes and in non-English locales.
  **[planned: `fable/clock-tiles`]**
- **F-L8. Items pane promises "⌫ to remove" but the List has no selection** —
  keyboard removal is impossible; and `.onDelete` removes by index while
  mutating, so a future multi-delete would remove the wrong rows.
  **[planned: `fable/unique-tile-ids`]**
- **F-L9. DisplaysView gates `NSScreen.localizedName` behind macOS 14** — the
  API exists since 10.15; the one OS that hits the fallback (13, the min
  target) gets "Display 1/2" on the very pane whose job is telling displays
  apart. **[planned: `fable/settings-panes`]**
- **F-L10. NowPlaying's H17 safety net can let a stale callback overwrite a fresher snapshot**
  (`NowPlayingService.swift:25-34`): abandoned fetches aren't invalidated — a
  generation token closes the hole.
- **F-L11. TrashMonitor never re-arms** after `~/.Trash` is deleted/recreated
  (watches the dead vnode forever), and a failed `open()` silently disables the
  feature with no log or retry.
- **F-L12. Vertical docks give separators a full 52 pt slot** for a 1 pt line —
  4× the 12 pt gap the same separator gets horizontally
  (`DockLayout.tileExtent`). Needs a coordinated layout+view+tests change.
- **F-L13. `DockLayout.hiddenFrame`/`edgeReveal` are dead code** — hiding is
  done by `hiddenTransform()`, which ignores them; only the tests exercise
  them. Delete or re-route so the pure function is the source of truth again.
- **F-L14. `AppLauncher.open(_ item:)`/`resolvedURL(_:)` are dead code** — and
  they silently disagree with the live path (no bookmark write-back), a trap
  for the first future caller. (See the M37 correction below.)
- **F-L15. Update checker lies "You're up to date"** when either version fails
  to parse, and a user-initiated check while a background check is in flight
  silently does nothing.
- **F-L16. Launch-at-login failure is swallowed** — with the login item
  disabled in System Settings or `.requiresApproval`, the toggle just snaps
  back with no explanation. `SMAppService.openSystemSettingsLoginItems()`
  exists precisely for this.
- **F-L17. Main menu lacks Settings… (⌘,) and Close Window (⌘W)** — with the
  Settings window focused, ⌘W beeps and ⌘, does nothing.
  **[planned: `fable/lifecycle-basics`]**
- **F-L18. `applicationSupportsSecureRestorableState` not implemented** —
  avoidable launch warning on macOS 14+. **[planned: `fable/lifecycle-basics`]**
- **F-L19. "Lock Screen" only sleeps the display** (prior-review H22,
  confirmed): with "require password after 5 minutes", the screen turns off
  *unlocked*. **[planned: `fable/lock-screen`]**
- **F-L20. Entitlements comment misdescribes the automation key** as a
  "temporary exception" (that's a different, sandbox-only mechanism).
  **[planned: `fable/docs-truth`]**

---

## Performance

- **F-P1. Icon cache TTL causes a synchronized re-resolve storm every 5 minutes**
  (`IconCache.swift:24-29`, `DockModel.swift:41`): all entries are inserted in
  the same rebuild and expire in the same second; the next rebuild then calls
  `NSWorkspace.icon(forFile:)` for *every* tile back-to-back on the main
  thread, forever, in lockstep. Distinct from prior-review M1 (first-resolve
  cost): the TTL design guarantees the worst case recurs. Fix: jitter per-entry
  age, or serve-stale-while-revalidate.
- **F-P2. Hovering a folder tile does synchronous bookmark I/O on the main thread up to 3× per hover**
  (`DockController.swift:269,300,394` → `DockStore.resolvedURL`): sweeping the
  pointer across folder tiles triggers bursts of disk I/O exactly while the
  magnification animation runs; a stale bookmark even triggers a store save +
  full rebuild cascade mid-hover. The hover-eligibility check doesn't need to
  resolve anything.
- **F-P3. Every 2 s sample fires 3–4 `objectWillChange` publishes**
  (`LiveSystemStats.swift:82-92`): the battery tile re-renders 15× more often
  than its data changes; a battery-only dock still runs the CPU/mem/net
  syscalls nobody displays. **[planned: `fable/sampler-accuracy`]** (equality
  gates; the source-splitting is follow-up)
- **F-P4. `RunningAppsModel.refresh()` publishes identical snapshots**
  (hide/unhide notifications can't change the Equatable array — the info
  carries no hidden flag) — each costs a full `rebuildModel()` +
  `relayoutPanels()`.
- **F-P5. Settings panes re-do global work per render**: MenuView validates ~47
  SF Symbols via `NSImage` allocation on every keystroke of the custom-symbol
  field; WidgetsView re-sorts ~600 time-zone ids per render; DisplaysView
  recomputes display UUIDs per body (prior-review M23, confirmed).
  **[planned: `fable/settings-panes`]**
- **F-P6. `TileAccent` allocates a fresh `CIContext` per icon** and grows an
  unbounded static cache (prior-review H16, confirmed — CIContext is documented
  as expensive). **[planned: `fable/tile-accent-cache`]**
- **F-P7. `BoingBallDecoration`'s single-slot bitmap cache thrashes on mixed-DPI
  multi-monitor** — two panels with different `displayScale` alternately evict
  each other's rasterized sphere (a ~60–250k-sample CPU loop) on every shared
  render trigger, breaking the cache contract its comment promises.
- Confirmed still open from the prior review (call-paths re-verified): **H7**
  (MediaRemote 5 s controller polling), **H14** (DateFormatter per clock
  render — **[planned: `fable/clock-tiles`]**), **M1/M3/M4/M5/M7** (main-thread
  icon resolution, per-relayout `invalidateShadow`, timers while hidden,
  main-thread sampler syscalls, unthrottled mouse-move fan-out), **M13**
  (recents stat() per keystroke), **M24/M25/M26** (ItemsView icons per render,
  permissions 2 s poll — poll relaxed in `fable/settings-panes` — and folder
  stack icon loads before the 128 cap).

---

## Visual & layout

- **F-V1. Hover name labels are clipped by the panel — fully invisible with
  magnification off, and always invisible on top-edge docks**
  (`DockTileView.swift:198-208` `.offset(y: -baseSize * 0.75)` + panel
  `masksToBounds`): with defaults the label sits above the panel's top edge;
  magnification headroom is the only thing that ever lets part of it show.
  "Show name on hover" silently does nothing for many configurations, and the
  offset direction is bottom-dock-specific (vertical docks pop the label over
  the neighboring tile). Needs an edge-aware offset plus reserved label
  headroom in `contentSize()`. needs-device-verify.
- **F-V2. Wide widget tiles overflow the glass strip on vertical docks**
  (clock 1.6×, now-playing wider): the strip is drawn at a fixed
  `iconSize + 2·padding` across-thickness while `DockLayout.contentSize`
  correctly sizes the *panel* from the widest tile — the widget floats past the
  glass; in overflow-scroll mode it's cropped by the viewport.
- **F-V3. Drag-out-to-remove: the tile vanishes under the panel mask long before
  the removal threshold** (~26–40 pt of visible travel vs the required ~83 pt;
  with magnification off there's no headroom at all) — the user drags an
  invisible tile with no cue that release will remove it.
- **F-V4. Active-glow dots and peek/stack anchors are misplaced in
  overflow-scroll mode** — both re-derive layout math that assumes the centered
  non-scrolled layout, and neither tracks the scroll offset. Suppress glows in
  overflow, or read real tile frames via anchor preferences.
- **F-V5. End tiles clip when the dock nearly fills the screen** — in the band
  where the panel is clamped to `visibleFrame` but not yet overflowing, the
  magnification headroom has been eaten but magnification stays on (residual
  ISSUE-2 regression).
- **F-V6. `GlassBackground` reads Reduce Transparency non-reactively** — nothing
  re-renders when the user toggles the accessibility setting; the fix is the
  `@Environment(\.accessibilityReduceTransparency)` key.
- **F-V7. AngleDial's doc (and GlassBackground's) claim the angle increases
  clockwise; the math is counterclockwise** — self-consistent, so behavior is
  fine, but anyone hand-writing `gradientAngle` in a preset JSON is misled; the
  Angle row is also the only control in the pane with no numeric readout.
  **[planned: `fable/preset-hardening`]**
- Confirmed still open: **H8** (magnified tiles overlap neighbors — the
  neighbor-shift integral remains the single biggest "feels like the real Dock"
  win), **M10** (white-on-light selected row in the menu —
  **[planned: `fable/menu-view-polish`]**), **M29** (clock minute lags up to
  30 s — **[planned: `fable/clock-tiles`]**), **M30** (battery glyph —
  **[planned: `fable/battery-tile`]**), **M33** (pomodoro `mm:ss` overflow ≥
  60 min — **[planned: `fable/pomodoro-robustness`]**).

---

## UX & product gaps

- **F-U1. The dock can silently cover the real Dock's territory while both are
  visible** — see F-H3; the two "docks fighting" state is reachable from
  supported settings.
- **F-U2. No first-run onboarding at all**: launch → menu-bar glyph appears and
  the system Dock vanishes (F-M15). A single welcome panel ("here's how to
  reveal, here's Restore, here's Settings") would remove the scariest moment of
  the product. The `!store.loadedFromDisk` seed path is the natural hook.
- **F-U3. Keyboard access is mouse-first everywhere**: menu power row
  unreachable by keyboard (prior M16), no ⌘1–9 result jumps, no ⌘C on
  calculator results (prior M14), Items pane ⌫ broken (F-L8), no ⌘,/⌘W (F-L17).
  The `fable/menu-view-polish` and `fable/lifecycle-basics` branches close part
  of this; the rest is tracked.
- **F-U4. Hover-to-select and always-visible web search in the menu** (prior
  M11, confirmed): mouse hover doesn't move the selection, and the web-search
  row disappears whenever any app matches. **[planned: `fable/menu-view-polish`]**
- **F-U5. No "No results" state in the menu** (prior M17, confirmed) — an empty
  scroll area reads as a bug. **[planned: `fable/menu-view-polish`]**
- **F-U6. Minimized windows are invisible in Jetty** — the system Dock shows
  minimized windows as thumbnails; Jetty's window-peek names mode lists windows
  but nothing marks minimized ones, and there's no "unminimize" affordance.
  With the AX machinery already shipped (opt-in), a ⊖ badge in WindowPeek rows
  is cheap. (Product gap, needs design.)
- **F-U7. `animationMs` is a fully-plumbed preference with no UI** — persisted,
  clamped, consumed by the reveal animation, reachable only via
  `defaults write`. One slider in General ▸ Behavior. **[planned: `fable/settings-panes`]**
- **F-U8. Update download has no feedback** (F-M14 sibling): after clicking
  Download, nothing indicates progress or completion; failure opens an
  unexplained browser tab.
- **F-U9. Settings slider ranges disagree with model clamps** (reveal delay
  0–600 vs 0–1000; hide 0–1500 vs 0–2000; inset 0–80 vs 0–400): hand-edited or
  future-version values render as a pinned thumb with a contradicting label,
  and the first drag silently rewrites them. Needs a one-source-of-truth
  decision rather than a blind edit.
- Confirmed open UX items from the prior review worth re-flagging: **H21**
  (denied Automation permission fails silently), **M8** (empty dock renders an
  empty glass strip), **M9** (offset slider is a silent no-op at alignment
  extremes), **M20/M21** (widgets expose nothing to VoiceOver; settings a11y
  gaps), **L25/L40** (no reset-to-defaults, no settings search).

---

## Release engineering, CI, tests & docs

- **F-R1. Prerelease tags ship as stable** — see F-H7. **[planned: `fable/ci-release-hardening`]**
- **F-R2. The release pipeline never runs tests** (and CI never compiles the
  Release configuration): a tag on a broken commit publishes a release the
  in-app updater immediately offers to everyone. With no signing/verification
  downstream (prior C1/C2 still open), tests are the *only* automated gate —
  and the release path skips it. **[planned: `fable/ci-release-hardening`]**
- **F-R3. `ci.yml` has no `permissions:` block** — the prior review's "minimal
  permissions" praise is only true of release.yml. `contents: read` is one
  stanza. **[planned: `fable/ci-release-hardening`]**
- **F-R4. No `timeout-minutes` anywhere** — a wedged xcodebuild (a failure mode
  `scripts/build.sh` itself documents) burns 6 h of 10×-billed macOS runner
  time, and on the release path silently stalls a release for 6 h.
  **[planned: `fable/ci-release-hardening`]**
- **F-R5. CI concurrency cancels in-progress runs on `main`, not just PRs** —
  two quick merges leave the first commit with a permanently "cancelled"
  status, masking breakage and punching holes in CI-status bisection.
  **[planned: `fable/ci-release-hardening`]**
- **F-R6. UpdateDownloader tests aren't hermetic** — they run `uniqueDestination`
  against the real `/tmp`; a leftover `Jetty.dmg` makes them fail spuriously.
  The repo's own `MenuGlyphAndStoreTests` shows the right per-test temp-dir
  pattern.
- **F-R7. Three tests cement open-backlog bugs as spec** (battery charging
  glyph, empty-dock placeholder size, `#FFF` rejection): whoever fixes
  M30/M8/L10 hits "regressions". The battery one is updated together with
  `fable/battery-tile`; the others should be annotated as characterization
  tests.
- **F-R8. Freshly-landed fixes (M27/M28/H6-offset) have no regression tests**
  despite being pure and injectable — partially covered by the new tests in
  `fable/preset-hardening`.
- **F-R9. `DockStore`'s `.bak` rotation — the app's core data-safety mechanism —
  has no unit test** despite full injectability. Three cheap tests would cover
  recover-from-corrupt-primary, don't-overwrite-good-bak, and round-trip.
- **F-R10. build/release scripts exec an unpinned external engine**
  (`lkm-build`/`lkm-release` from PATH or an env override) with no version or
  integrity check — the release *tagging* step depends on whatever binary is
  installed.
- **F-R11. README/AGENTS drift**: window previews are described as
  "coming-soon" but shipped (and the README feature list never mentions them);
  the folder bullet describes the old click behavior; AGENTS.md claims the
  Jetty Menu switches activation policy (it deliberately doesn't — the code's
  approach is better than the doc). **[planned: `fable/docs-truth`]**
- Prior **C1/C2/C3** (no update verification, unsigned releases, floating
  action tags) are confirmed untouched and remain the top security items. They
  need maintainer-held secrets/keys, so no PR is attempted here — but F-R1–F-R5
  shrink the blast radius meanwhile.

---

## Corrections to REVIEW.md

Things the prior review got wrong, now verified:

1. **L3 is invalid.** `releaseNotes()` truncation cannot split a grapheme
   cluster: `String.count` and `String.index(_:offsetBy:)` on `String` stride
   by `Character`, which *is* an extended grapheme cluster. Close it.
2. **M37's premise is stale.** `AppLauncher.resolvedURL` is not "used on every
   tile click" — that path is dead code; the live click path already routes
   through `DockStore.resolvedURL(forItemID:)` with bookmark write-back. The
   right fix is deleting the dead entry point (F-L14).
3. **H7/M4 cite `Jetty/Menu/NowPlayingWidgetView.swift`** — the file lives
   under `Jetty/Widgets/`.
4. **"CI basics are right: … minimal `permissions:`"** — only release.yml has a
   permissions block; ci.yml has none (F-R3).
5. **AGENTS.md's activation-policy claim** — the Jetty Menu never goes
   `.regular`; only Settings does (and the menu's actual approach is correct).

These corrections are applied to the docs in `fable/docs-truth`.

---

## Status of the prior backlog

Spot-verified against the current tree during this review — all **still open
and accurately described** unless listed in
[Corrections](#corrections-to-reviewmd): C1, C2, C3, H2*, H4*, H7, H8, H9,
H12*, H13, H14*, H15*, H16*, H21, H22*, H25*, M1, M3, M4, M5, M7, M8, M9, M10*,
M11*, M12*, M13, M14, M15*, M17*, M18*, M19*, M20, M21, M22, M23*, M24, M25*,
M26, M29*, M30*, M31, M33*, M35, M36, M38, M39 and the L-series.
Items marked `*` are addressed (fully or partly) by the branches below.

---

## New ideas

REVIEW.md already has a strong ideas list (squish-magnification,
bounce-on-launch, spring-loaded folders, badges, per-display personalities,
heat-map reveal, wake breathing, artwork, sun/moon/AQI tiles, calendar tile,
window switching in the menu, eyedropper, chords, settings search…). These are
*new* on top of it, each grounded in machinery that already exists:

1. **`jetty://` URL scheme + Shortcuts hooks.** `jetty://toggle`,
   `jetty://reveal?display=uuid`, `jetty://menu`, `jetty://preset/Vapor`,
   `jetty://pomodoro/start?minutes=50`. One `NSAppleEventManager` handler in
   `AppDelegate` fans out to `DockController`/`Preferences.apply` — instantly
   scriptable from Shortcuts, Raycast, shell (`open jetty://...`), BetterTouchTool.
   The unix-philosophy hook DragThing users still mourn.
2. **Scroll-wheel gestures on tiles.** Scroll over an app tile → cycle that
   app's windows (the `AppWindows` raise machinery is already shipped); scroll
   over the pomodoro → nudge minutes; over world clock → cycle favorite zones.
   `DockTileView` just needs a scroll monitor; everything downstream exists.
3. **Option-drag a tile = duplicate as floating mini-launcher** is REVIEW.md's
   drag-out-to-promise; new twist: **⌘-hover a tile to peek its *path*** in the
   label (power users constantly want "where is this app really?").
4. **Day/night auto-theming.** The weather tile already knows coordinates; a
   NOAA sunrise calculation is pure math. At sunset, cross-fade to a chosen
   preset (`Preferences.apply` exists; presets are shareable). "Vapor at night,
   Clear by day" is a screenshot-bait feature.
5. **Preset cards.** On export, also render the current dock into a PNG
   "theme card" (`NSHostingView` + `dataWithPDF`/bitmap rep of a 3-tile faux
   dock) so shared `.json` themes come with a preview — makes a community
   theme gallery viable.
6. **Per-tile launch hotkeys.** `⌥1…⌥9` activate the Nth dock tile —
   `CarbonHotkey` infrastructure is already there; the tile order is already
   stable and user-curated. (The system Dock never had this; uBar charges for
   it.)
7. **Trash X-ray.** `TrashMonitor` already watches the Trash; the tooltip (and
   VoiceOver value) could say "14 items · 3.2 GB" — one `contentsOfDirectory`
   with `totalFileAllocatedSize`, cached on the monitor's events. Pairs with
   IDEA-5's "hot" state.
8. **Pomodoro in the menu-bar glyph.** While the dock is hidden (95% of the
   time), the status item is Jetty's only visible surface: swap
   `statusBarImage()` for a tiny progress ring while a session runs. The
   timer's the one widget whose *absence* while hidden hurts.
9. **Haptic detents on magnification.** `NSHapticFeedbackManager.defaultPerformer
   .perform(.alignment)` as the hover crosses tile centers — Force-Touch
   trackpads turn the dock into something you can *feel*. Three lines in the
   hover handler, gated by a preference.
10. **"Focus dock" per Space/app.** When Screen-Recording-free window peek is
    on, Jetty knows the frontmost app; a rule like "when Xcode is frontmost,
    show only the Dev folder's tiles" (per-app tile filters) is a genuinely new
    dock capability — DockModel's pure merge makes the filter a one-liner; the
    UI is the work.
11. **Battery time-to-full/empty in the tooltip** — `IOPSGetTimeRemainingEstimate`
    is public and free; the battery tile's `.help` currently says just
    "Battery".
12. **Konami-code boing.** Typing "boing" in the Jetty Menu bounces the Amiga
    ball across the dock once (the `BoingBallDecoration` renderer + a keyframe
    animation). Zero-cost delight for the retro crowd the decorations already
    court.

---

## Implementation plan

Each branch is a self-contained PR off `main`, scoped to keep file overlap
between branches near zero (where two branches touch the same file, they touch
disjoint regions). No branch edits `REVIEW.md` except `fable/docs-truth`, to
avoid conflict fan-out.

| Branch | Fixes | Files |
|---|---|---|
| `fable/settings-restore-system-dock` | F-H2 | GeneralView |
| `fable/autohide-off-reveals` | F-H1 | DockController |
| `fable/menu-return-priority` | F-H4 (+ prior H2, M12, M18) | JettyMenuModel, MenuCommand, JettyMenuController (wiring), CommandBarTests |
| `fable/menu-focus-and-keys` | F-M2, F-M3, F-L3 (+ prior M15, M19) | JettyMenuController |
| `fable/menu-view-polish` | F-U4, F-U5 (+ prior M10, M11, M17) | JettyMenuView |
| `fable/search-diacritics` | prior H4 (+ L6) | AppSearch, AppSearchTests |
| `fable/appindex-finder-inflight` | F-L4 (+ prior H25) | AppIndex |
| `fable/calculator-precedence` | F-L1, F-L2 | ExpressionEvaluator, ExpressionEvaluatorTests |
| `fable/pomodoro-robustness` | F-H8(pomodoro), F-M7 (+ prior H12, M33) | PomodoroTimer, PomodoroWidgetView |
| `fable/weather-robustness` | F-H8(weather), F-M5 (+ prior H15) | WeatherService, WeatherWidgetView |
| `fable/clock-tiles` | F-L7 (+ prior H14, M29) | ClockFormatter, ClockWidgetView, WorldClockWidgetView |
| `fable/battery-tile` | F-L6 (+ prior M30, F-R7 battery test) | SystemStats (battery section), BatteryWidgetView, InfoWidgetTests |
| `fable/sampler-accuracy` | F-M6, F-P3 | LiveSystemStats, SystemStats (network section) |
| `fable/preset-hardening` | F-H5, F-M8, F-V7 (+ tests, F-R8 partial) | Preferences, AngleDial, AppearancePreset, CodableModelTests |
| `fable/settings-panes` | F-M9, F-M10, F-M11, F-L9, F-P5, F-U7 (+ prior M23, M25) | DisplaysView, HotkeyRecorder, WidgetsView, MenuView, PermissionsView, AppearanceView, GeneralView (Behavior section) |
| `fable/unique-tile-ids` | F-M1, F-L8 | DockModel, ItemsView, DockModelTests |
| `fable/lifecycle-basics` | F-H6, F-L17, F-L18 | AppDelegate |
| `fable/ci-release-hardening` | F-H7, F-R2–F-R5 | ci.yml, release.yml |
| `fable/lock-screen` | F-L19 (prior H22) | PowerCommands |
| `fable/tile-accent-cache` | F-P6 (prior H16 part) | TileAccent |
| `fable/docs-truth` | F-M15 (wording), F-R11, F-L20, REVIEW.md corrections | README, AGENTS, REVIEW, Jetty.entitlements |

Deliberately **not** implemented here (needs a live GUI, a compiler, or a
product decision): F-H3 (inset stretch), F-V1–F-V5, F-M4 (AppleScript
threading), F-M12–F-M14, F-U2 (consent flow), F-U6, F-U9, F-P1/F-P2/F-P4/F-P7,
H8/H9/H13 from the prior backlog, and the C1–C3 release-security work (needs
maintainer keys). They're documented above so none of it gets lost.

---

## What's genuinely good

The prior review's "done well" list still holds, and a fresh pass adds:

- The **reveal/hide rework** (window parked, content-layer transform only) is
  the right architecture — pure GPU compositing, no SwiftUI re-layout
  mid-slide, and the mid-animation convergence guard shows real care.
- **`Failable`/lossy decoding, the `.bak` rotation guard, and the seam-crossing
  reveal geometry** (`pointerCrossedEdge` with hysteresis bands) are all
  unusually thoughtful for a v1.
- The **pure-logic discipline is real**: nearly every behavior worth testing
  (layout, merge, magnification, search, conversion, parsing, clamping) is a
  value-typed function with tests. That's what made this review — and the
  fixes that follow — cheap and safe to do.
- The **dedup comment in `DockModel.makeSlots`** documents *why* an invariant
  matters (magnification desync), which is exactly what let this review spot
  that the invariant wasn't fully enforced. Comments that state invariants pay
  compound interest.

*Reviewed against `main` @ `571ab6e`, 2026-07-01. Line numbers current as of
that commit.*
