# Jetty review

Reviewed 2026-07-10 at `main @ a33cb74` (`Full Trash display fix`).

This is a current-state static review of the application, tests, project settings,
release workflows, and product documentation. It pays particular attention to the
two most recent Trash commits rather than repeating the older state described in
`REVIEW.md`.

The review host is Linux and has neither Xcode nor Swift installed, so I could not
compile, run the unit suite, launch Jetty, use Accessibility Inspector, or profile
with Instruments. Findings marked **confirmed** follow directly from code. Findings
marked **profile** or **manual** need validation on a Mac. Existing tests were read
and assessed but not executed.

## Verdict

Jetty has a good architecture and a much broader feature set than most personal Dock
projects. The load-bearing choices are sound: nonactivating panels, no screen-space
reservation, no Accessibility dependency in the core, stable model/layout helpers,
atomic document writes, and isolated optional private APIs.

The main problem is not a weak foundation. It is that several expensive or fallible
operations have leaked into the main-thread interaction path, while the UI often
assumes they succeeded. The most visible examples are Trash state discovery, file
trashing, AppleScript commands, icon resolution, system sampling, window previews,
and bookmark resolution. There are also a few headline-product mismatches: first
launch hides Apple's Dock without consent, edge inset is ineffective on three edges,
magnified tiles overlap, minimized windows are absent, and release artifacts are not
signed or verified.

The reported Trash problem is credible even after the latest fixes. The current code
selects the correct native empty/full images and accounts for per-volume Trash folders,
but it can still remain stale across mount, wake, lazy folder creation, or a partial
watch failure. It also performs more synchronous directory work than the comments
claim. Drag targeting now has a subtle outline, but there is no strong Trash-specific
affordance, accepted/success/failure state, or error surface. Clicking has no pressed
or completion feedback.

## What is already strong

- The core Dock remains permission-free. There is no global key monitor or event tap,
  and the dock does not move other applications' windows.
- Dock panels are nonactivating, join all Spaces, support fullscreen, and reveal by a
  layer transform rather than frame animation (`DockPanelController.swift:82-120,
  424-455`). That is the right anti-stutter architecture.
- `DockLayout`, `DockModel.makeSlots`, magnification math, search, calculator,
  conversion, clock formatting, folder geometry, weather parsing, and version parsing
  are kept testable and mostly pure.
- `DockStore` uses atomic primary writes, lossy element decoding, a protected backup,
  and future-version write protection.
- The current Trash code correctly treats hidden discarded items as content, ignores
  `.DS_Store`, normalizes a pinned Trash folder to the built-in tile, bypasses custom
  icons, and prefers a full icon when state is unreadable (`DockModel.swift:224-317`).
- The current Trash drop overlay does not intercept hits, and only app/Trash tiles
  advertise specific file-drop behavior (`DockTileView.swift:219-230`,
  `DockView.swift:301-332`).
- Folder enumeration and thumbnail capture are at least moved out of direct SwiftUI
  body evaluation, stale publications are guarded, and caches exist for common icon
  paths.
- The optional private APIs are isolated and generally fail closed instead of taking
  down the dock.
- Recent fixes for running-app equality, duplicate IDs, bookmark refresh on normal
  click, store version stamping, weather retries, and IME-safe menu handling are
  present. Several matching entries in `REVIEW.md` are stale and should not be carried
  forward as open work.

## Critical

### C1. Updates are downloaded without authenticity verification

**Confirmed.** `UpdateDownloader.swift:25-38`, `UpdateChecker.swift:181-201`,
`GitHubRelease.swift:17-27`.

The updater trusts downloaded bytes after an HTTP status check. It does not validate a
signed manifest, SHA-256, detached signature, expected Team ID, code signature, or
notarization. It also does not constrain redirects/asset hosts or compare the decoded
GitHub `size` to the downloaded file.

This makes the updater a delivery mechanism for whatever bytes the release endpoint
serves. Quarantine is useful but is not publisher authentication, especially while the
README and release notes teach users how to remove it.

Recommended end state: sign releases with Developer ID and hardened runtime, notarize
and staple them, publish a signed hash manifest, validate the asset before moving it to
Downloads, and verify the extracted application's designated requirement and Team ID.
As a small independent baseline, reject a downloaded file whose byte count differs
from GitHub's advertised size.

### C2. The release workflow publishes unsigned artifacts and recommends bypassing Gatekeeper

**Confirmed.** `.github/workflows/release.yml:21-119`, `README.md:135-140`.

CI disables signing, applies only an ad-hoc signature, does not notarize, and publishes
instructions for `xattr -dr com.apple.quarantine`. This contradicts the distribution
claim immediately above it and combines badly with C1.

The correct fix needs maintainer credentials and secret-management decisions, so it is
not an opportunistic code change. The release job should fail closed when credentials
are absent, sign with hardened runtime and the checked-in entitlements, notarize,
staple, verify with `codesign --strict` and `spctl`, and publish hashes/provenance.

### C3. Release-producing dependencies are mutable

**Confirmed.** `.github/workflows/ci.yml:30-38`,
`.github/workflows/release.yml:25-33,98-100`, `scripts/build.sh`,
`scripts/release.sh`.

GitHub Actions use floating major tags, Homebrew installs current formulae at release
time, and local scripts execute a release engine from `PATH` or an environment
override. Pin actions to full commit SHAs, pin tool versions/checksums, verify the
release-engine identity, and emit artifact hashes/provenance.

## High priority

### H1. Trash state is still stale in several real lifecycle paths and its probe is on the main thread

**Confirmed.** `TrashLocations.swift:31-72`, `TrashMonitor.swift:39-85`,
`DockController.swift:59-97,121-150`, `DockModel.swift:82-100,257-317`.

The latest commits fixed important pieces: home and per-volume candidate directories
are considered, native empty/full images are selected, vnode delete/rename events
re-arm, and a successful Jetty-originated drop rebuilds immediately.

Residual correctness failures remain:

- A drive mounted after launch is not observed. There are no volume mount/unmount/
  rename observers in the Trash pipeline.
- If a volume has no `.Trashes` yet, its root is not watched, so Finder's lazy creation
  of the first `.Trashes` folder is invisible.
- Wake only reasserts the system Dock; it does not re-arm or rescan Trash.
- The event mask omits `.revoke`.
- Retry is global. If one desired path opens and another fails, `openedAny` suppresses
  retries for the failed path. A home Trash replacement can therefore remain unwatched
  indefinitely while a volume parent is still watched.
- Startup scans state before the watcher is armed, leaving a scan-before-watch race.

The state probe is also more expensive than its comments imply. Every model rebuild
calls `contentsOfDirectory(atPath:)` for each candidate before falling back to
`readdir`, materializing the complete contents of a large Trash on the main thread.
Every monitored event first runs `trashDebugSummary()` and then rebuilds, scanning the
candidates twice. Running-app changes can trigger the same I/O even when Trash itself
did not change.

Recommended staged fix:

1. Make the first-real-entry `readdir` probe the primary bounded path and remove the
   production diagnostic rescan.
2. Track desired watch paths and failed paths independently; retry partial failures,
   watch a parent/root while a lazy Trash directory is absent, and handle `.revoke`.
3. Refresh watches and state on mount, unmount, rename, and wake.
4. Start monitoring only while a Trash tile exists and arm before the initial scan.
5. Ultimately move discovery/probing to one serialized utility worker and publish a
   cached `empty/full/unknown` value to `DockModel` on the main actor.

Tests should inject directory/volume discovery and prove bounded probing, partial
failure retries, lazy parent creation, mount/unmount, wake, vnode replacement, and one
state scan per coalesced event.

### H2. Trash interaction feedback is incomplete and failures are invisible

**Confirmed for missing feedback; manual for the current overlay's perceptibility.**
`DockTileView.swift:32-55,219-276`, `DockController.swift:521-531,638-647`,
`AppLauncher.swift:53-68`.

Clicking is an `onTapGesture` with no pressed state or Trash-specific response. During
a drag, the tile gets the same tint-colored rounded outline used elsewhere; it does not
communicate the destructive operation strongly and gives no accepted/success/failure
state. The SwiftUI drop is reported accepted before URL decoding or filesystem work.

`moveToTrash` returns only a count and logs per-file errors. Total and partial failures
look the same as success to the user. Moving multiple items is synchronous on main.
Empty Trash similarly blocks on AppleScript and logs failures only.

Add a clear Trash-specific target state, a brief accepted/success animation, pressed
feedback on click, and an accessible value/action. Move filesystem work to a serial
utility queue, return moved URLs plus per-item errors, and show a concise partial/total
failure message. A playful but restrained lid wobble or short "gulp" after a successful
drop would suit Jetty; it should respect Reduce Motion.

### H3. First launch hides Apple's Dock before consent or instruction

**Confirmed.** `Preferences.swift:46-52`, `AppDelegate.swift:32-49`,
`DockController.swift:59-68`, `DockPanelController.swift:146-151`,
`PLAN.md:482-494`.

`manageSystemDock` and auto-hide both default to true. Launch immediately changes global
Dock defaults and restarts Dock, while Jetty's own panel starts invisible. The user has
not agreed, learned the reveal edge, or seen Restore System Dock. This violates PLAN's
explicit first-run consent and creates the app's worst trust moment.

Add a one-time onboarding handoff before modifying Dock defaults: explain what changes,
offer Try Jetty / Keep Apple Dock Visible / Quit, require one successful Jetty reveal,
and keep Restore visible throughout. Persist completion separately from `dock.json`.

### H4. Edge inset is ineffective on bottom, left, and right

**Confirmed by geometry; manual four-edge verification required.**
`DockLayout.swift:119-147`, `DockPanelController.swift:363-383`,
`DockView.swift:40-55`, `README.md:22-25`.

`DockLayout` applies inset correctly, then `recomputeFrames()` stretches the panel back
to the physical edge. `DockView` aligns the glass to that stretched edge, erasing the
inset on three edges. The same stretch can place Jetty over a visible Apple Dock.

Keep the panel/glass at the pure layout frame. If Fitts-law edge behavior is desired
for zero inset, implement it as a narrow hit target rather than changing the visual
frame. Test all edges with inset 0/20/80 and Apple Dock both managed and visible.

### H5. Transparent dock headroom and the edge drag sensor can swallow unrelated input

**Confirmed mechanism; manual hit testing required.**
`DockPanelController.swift:97-103,320-353,427-455,474-510`,
`DockView.swift:48-63`, `DockTileView.swift:61-67`.

The window budgets large transparent headroom for magnification and clock zoom, the
whole host receives a rectangular content shape, and the panel accepts mouse events
while revealed. Visible clock content can extend outside its base hit frame, while
invisible headroom can block clicks to the app beneath. The permanent six-point sensor
is a very high-level panel and is not mouse-transparent.

Use actual presentation-frame tile and glass hit regions, returning nil outside them.
Validate whether AppKit drag registration survives `ignoresMouseEvents`; otherwise
activate a lower-level sensor only during drag sessions. Test every edge and maximum
clock zoom over scrollbars, traffic lights, menus, and ordinary content.

### H6. Magnification overlaps neighbors instead of moving the row apart

**Confirmed mathematically; manual tuning required.** `DockTileView.swift:58-66`,
`DockView.swift:242-328,403-433`, `Preferences.swift:26-30`.

A default 52-point tile at 1.5x gains 13 points on each side, exceeding the default
eight-point gap. Tiles are scaled in place and only z-order changes, so they collide.
Wide widgets amplify the effect.

Compute neighbor displacement from cumulative magnification and use one geometry result
for centers, rendered frames, glows, drag targets, hit testing, and popover anchors.
This is likely the single largest improvement to the "real Dock" feel.

### H7. System Monitor values are not the values their labels imply

**Confirmed.** `SystemStats.swift:59-68,92-118`,
`LiveSystemStats.swift:33-40,81-92`, `SystemMonitorWidgetView.swift`.

"CPU" is one-minute load average divided by core count, not CPU utilization. It reacts
slowly and can disagree sharply with Activity Monitor. Network totals come from 32-bit
`if_data` counters that wrap at 4 GB, and rates always divide by two seconds rather than
actual monotonic elapsed time. Sleep, timer coalescing, or main-thread stalls can create
large false spikes; a wrap creates a zero dip.

Use `HOST_CPU_LOAD_INFO` deltas for utilization, `NET_RT_IFLIST2` 64-bit counters, and
monotonic elapsed time. Reset the baseline/history after a long gap or wake. Move reads
to a utility queue and publish one atomic sample. Unit-test variable intervals, wraps,
interface resets, and long suspension.

### H8. Now Playing can leak work and accepts a late response after timeout

**Confirmed, opt-in.** `NowPlayingService.swift:19-45`,
`MediaRemoteBridge.m:75-141`, `NowPlayingWidgetView.swift:11-17`.

On 15.4+, every refresh creates a controller and main-queue dispatch timer polling every
60 ms. The event handler captures the source that owns the handler; cancellation does
not break that cycle. The legacy path repeatedly `dlopen`s and never closes or caches
the handle. The Swift timeout clears `inFlightGeneration` without invalidating the
generation, so a late callback before the next refresh can still publish.

At minimum break the dispatch-source cycle, cache the legacy handle/function once, and
invalidate the generation on timeout. The better design is one long-lived controller
or MediaRemote notifications with a centralized freshness gate. Verify with Allocations
and Leaks for 30-60 minutes, including no media playing and multiple displays.

### H9. Window Peek duplicates enumeration and cannot cancel obsolete captures

**Confirmed, opt-in.** `WindowPeekController.swift:25-43`,
`WindowPeek.swift:19-65`, `AppWindows.swift:19-86`.

Opening a peek synchronously enumerates windows in the controller, then the model does
it again, then immediately starts another async enumeration. Thumbnail mode captures
every target sequentially at up to 800 pixels and repeats every second. The task is not
stored; close or rapid retarget only suppresses stale publication, not expensive work.
An obsolete generation can keep `isRefreshing` true and delay the current target.

Pass the initial list into the model, store/cancel the refresh task, check cancellation
between captures, and publish one generation-tagged snapshot. Capture near displayed
size and use a slower/event-driven topology cadence. Profile an app with 10-30 windows
while rapidly traversing tiles.

### H10. Background update checks can steal focus

**Confirmed.** `UpdateChecker.swift:89-151,224-235`.

Automatic checks call the same activating modal alert as a user action. A launch-at-
login check can interrupt typing and leave an accessory app frontmost after dismissal.
Download progress is unobserved and download failure silently opens a browser.

Use a notification or defer presentation until a user gesture. Centralize activation
capture/restore with Finder fallback, surface progress/failure, and queue a manual check
that arrives while a background check is in flight.

### H11. Power commands and Trash mutations block main and report failures only to Console

**Confirmed.** `PowerCommands.swift:82-104`, `MenuCommand.swift:49-54`,
`JettyMenuController.swift:133-168`, `DockController.swift:521-531,638-647`,
`AppLauncher.swift:60-68`.

AppleScript can wait for TCC consent or an AppleEvent timeout. File trashing can wait on
slow/removable volumes. Both run synchronously from main-thread UI callbacks. The menu
closes before scripts execute, and errors are logged only. Dock Empty Trash activates
Jetty for a modal alert but does not restore the previously frontmost app.

Use dedicated serial workers, asynchronous `Result` values, visible progress/errors,
an Automation Settings link, and one reusable focus-handoff coordinator.

### H12. Display collision keys do not round-trip

**Confirmed.** `DisplayRegistry.swift:29-53,65-72`,
`DisplaysView.swift:55-64`, `DockController.swift:348-358,507-518`.

`rebuild()` assigns `UUID#2` to collisions, but `key(for:)` recomputes only the base
UUID. Both screens can therefore resolve to the same panel/settings identity. Suffixes
are order-dependent, and UUID-less displays use session-local display IDs despite the
unqualified stable-restore promise.

Persist a reverse map from each current display ID to its assigned key and expose
resolved display entries to all callers. Make suffix assignment deterministic where
hardware permits and document session-only fallback. Make the registry observable so
Settings refreshes when displays change.

### H13. Backup rotation can delete the last good backup before replacement succeeds

**Confirmed.** `DockStore.swift:166-194`, `StoreBackupTests.swift:34-73`.

Saving removes `.bak`, ignores failure copying the good primary, then writes the new
primary. A disk-full or permission error can erase the recovery copy. Existing tests
cover healthy rotation and corrupt-primary protection but not replacement failure.

Copy the current primary to a temporary backup, decode/verify it, then atomically
replace `.bak`. Never remove the old backup until its replacement exists. Add fault-
injected copy/replace tests and surface persistent save failures.

### H14. "Lock Screen" can fall back to a state that is not immediately locked

**Confirmed.** `PowerCommands.swift:107-136`, `Settings/MenuView.swift`,
`PowerCommandTests.swift`.

The private immediate-lock function's return value is ignored. If symbol resolution
fails, Jetty starts the screen saver, whose password delay may leave the session
unlocked, while the UI still says Lock Screen. Documentation and tests describe older
implementations.

Treat missing symbols and non-success returns as a visible failure. If the only fallback
is the screen saver, label it accurately and never imply an immediate lock.

### H15. Core Dock accessibility is presentational rather than operational

**Confirmed; manual VoiceOver validation required.** `DockTileView.swift:38-55,
81-95`, `DockPanelController.swift:82-95`, widget views.

Tiles use tap gestures plus a button trait but no explicit default accessibility action.
Children are ignored and only running applications expose a value, so VoiceOver cannot
hear clock time, Trash state, battery, weather, CPU/RAM, track, or Pomodoro status.
Separators are exposed as elements. The nonactivating dock has no keyboard navigation
path.

Add default and named accessibility actions, hide separators, publish dynamic per-kind
values, and provide a hotkey-driven keyable Dock Navigator for full keyboard operation
without adding a global key monitor.

## Medium priority

### M1. Root preference observation causes broad invalidation and queued duplicate work

**Confirmed; profile magnitude.** `Preferences.swift:141-223,344-366`,
`DockView.swift:10-16`, `DockTileView.swift:8-16`,
`DockController.swift:132-172`.

Every dock, tile, and several widgets observe one object with dozens of published
properties. Preset application assigns fields individually. The controller queues an
uncancelled main work item for every `objectWillChange`. Split render domains or pass
small equatable configurations, coalesce controller reconciliation, and batch preset
application.

### M2. Model/store changes cause redundant rebuilds and panel frame work

**Confirmed.** `DockController.swift:127-143,203-221,403-408,533-537`,
`DockPanelController.swift:126-141`, `DockModel.swift:82-100`.

`DockModel` publishes slots and tiles separately. Store changes queue rebuild and panel
reconciliation even though rebuild already relayouts. `DockPanelController.update`
recomputes frames and immediately calls a method that recomputes again. Bulk URL drops
mutate the store once per item. Add atomic snapshots/batch mutations, coalesce store
work, diff geometry before relayout, and remove duplicate frame recomputation.

### M3. Magnification and reordering do avoidable pointer-frequency work

**Confirmed structure; profile impact.** `DockView.swift:18-23,173-195,
242-283,362-433`.

Every continuous-hover point mutates root state and recalculates centers, glows,
z-indexes, scales, and animations. During drag, every slot recomputes all extents and
the target, producing roughly quadratic work. Cache geometry until structure changes,
calculate one scale/offset snapshot per event, and coalesce pointer input to display
cadence. Profile 20/50/100 tiles with a high-polling mouse.

### M4. Hidden docks continue expensive periodic work

**Confirmed for `LiveSystemStats`; profile `TimelineView` scheduling.**
`DockController.swift:212-218`, `LiveSystemStats.swift:44-92`,
`ClockWidgetView.swift`, `WeatherWidgetView.swift`, `NowPlayingWidgetView.swift`.

Sampler demand is based on panel existence, not reveal state. Battery-only demand still
samples CPU, memory, and network every two seconds; system-monitor-only demand still
polls battery. Panels hide by transform, so widget views remain mounted. Track separate
demand/visibility, pause expensive work when no panel is visible, refresh immediately
on reveal, and use timer tolerance.

### M5. Edge mouse monitoring runs when edge reveal cannot do anything

**Confirmed.** `EdgeHoverMonitor.swift:16-27`, `DockController.swift:71-74`,
`DockPanelController.swift:190-193`.

Global/local mouse monitors start unconditionally and route every movement through
every panel even when auto-hide is off or reveal is hotkey-only. Start/stop based on
effective demand and coalesce to display cadence while retaining immediate hard-edge
detection.

### M6. Icon caches have expiry cliffs, unbounded auxiliaries, and synchronous rendering work

**Confirmed.** `DockModel.swift:55,187-216`, `IconCache.swift`,
`TileAccent.swift`, `JettyMenuModel.swift:128-136`, `ItemsView.swift:131-160`.

Dock icons inserted together expire together after five minutes and synchronously
reload on the next rebuild. Accent extraction performs TIFF/Core Image work from the
render path and caches by tile ID even if the icon changes. Menu/accent dictionaries are
unbounded. Settings reloads icons while rendering rows. Use cost-limited caches,
stale-while-revalidate, icon-identity keys, off-main accent extraction, and downsampled
custom images.

### M7. Folder stacks cannot distinguish errors/truncation and do not cancel stale work

**Confirmed.** `FolderStack.swift:45-69,122-170,191-199`,
`FolderStackController.swift:75-87`.

Read failure and an empty folder both produce `[]`; the 128-entry cap is silent. A load
token suppresses stale publication but old enumeration/icon work continues after close
or retarget. Return a snapshot with error/truncated state, store a cancellable task,
check cancellation during work, and show "Couldn't read" / "Showing first 128".

### M8. Jetty Menu performs duplicate scans and unnecessary per-keystroke work

**Confirmed.** `AppIndex.swift:17-29`, `JettyMenuController.swift:18-20,68-70`,
`JettyMenuModel.swift:62-77,128-136`, `RecentAppsStore.swift`.

First construction starts an app scan and first show immediately starts another; the
generation suppresses stale publication but does not cancel the scan. Every query asks
the recents provider even though nonempty ranking ignores recents, and state is
published field by field. Use one cancellable/coalesced scan, query recents only for an
empty query, publish one menu state, and resolve icons asynchronously.

### M9. Currency rates are fetched on menu open rather than currency intent

**Confirmed.** `JettyMenuController.swift:68-69`, `CurrencyService.swift:17-35`,
`JettyMenuModel.swift:80-98`.

Opening the menu sends the user's IP to Frankfurter even for app search or calculator
use. Responses do not validate HTTP status/date, rates are session-only, and stale age
is not shown. Fetch only after a valid currency query, disclose/provider-toggle network
use, validate status/date, persist source age, and mark stale results.

### M10. Bookmark-backed actions are inconsistent

**Confirmed.** `DockController.swift:431-437,521-526,585-599`,
`BookmarkResolver.swift:15-24`.

Normal click resolves a moved item through its bookmark, but drag-to-open and Show in
Finder use stale tile URLs. Hovering a folder synchronously resolves bookmarks and can
mount or prompt for unavailable network volumes because resolution uses no
`withoutUI/withoutMounting` options. Route all explicit actions through one live URL;
use cheap metadata for hover and resolve after dwell off-main without mounting.

### M11. Launch failures are silent and recents are recorded before success

**Confirmed.** `AppLauncher.swift:28-50`, `DockController.swift:487-502`,
`JettyMenuController.swift:50-58`.

`NSWorkspace` completion handlers are discarded. A missing app can close the menu and
be recorded as recent before launch succeeds. Return asynchronous results, record only
success, surface failures, and carry exact bundle URL/PID when duplicate installations
share a bundle ID.

### M12. Hotkey recording and registration failures are invisible

**Confirmed.** `HotkeyRecorder.swift`, `DockController.swift:664-683`,
`CarbonHotkey.swift:68-83`.

Existing hotkeys remain registered while recording, duplicate assignments are accepted,
and registration Boolean results are ignored. Suspend registrations during capture,
reject conflicts, and show OS-owned/duplicate failures inline.

### M13. Launch-at-login approval states collapse into a Boolean

**Confirmed.** `Preferences.swift:225-233,369-395`, `GeneralView.swift:11-14`.

Only `.enabled` is represented. `.requiresApproval` looks off, errors merely snap the
toggle back, and disabling does not unregister a pending request. Model all statuses,
offer the Login Items settings link, and unregister pending registrations.

### M14. Store recovery/read-only/save-failure states are invisible

**Confirmed.** `DockStore.swift:12-43,166-207`.

The UI cannot tell whether primary, backup, or defaults loaded. A newer document allows
edits that will never persist; corrupt primary plus corrupt backup silently seeds a new
dock. Expose a load outcome and save error, disable mutations in read-only mode, and
offer backup restore/export rather than silently replacing state.

### M15. Hover labels are clipped and placed in the wrong direction

**Confirmed by layout; manual.** `DockTileView.swift:203-216`,
`DockPanelController.swift:320-353,97-103`.

Labels always offset upward, panel sizing does not reserve label space, and the
container clips. Top and vertical docks are wrong; bottom labels can disappear when
magnification is off. Use edge-aware tooltips or a separate anchored label panel with a
small dwell.

### M16. Drag-out removal becomes invisible and has no undo

**Confirmed by geometry; manual feel.** `DockView.swift:334-360`,
`DockPanelController.swift:97-103`, `DockController.swift:411-415`.

Removal requires 1.6 icon widths of perpendicular travel, usually beyond clipped panel
headroom. The user drags an invisible tile with no threshold cue, then deletion is
immediate. Use an unclipped floating ghost, an outward-only remove zone, a clear Remove
cue, and a short Undo toast.

### M17. Popovers are not coupled to dock auto-hide

**Confirmed.** `DockPanelController.swift:224-230`,
`DockController.swift:285-345`, `WindowPeekController.swift:46-67`,
`FolderStackController.swift:89-99`.

The dock schedules hide based only on its own frame while stack/peek controllers manage
separate grace periods. It can slide away under a child panel. Add a shared interaction
coordinator and a triangular hover corridor/tether.

### M18. Window preview controls over-promise without Accessibility

**Confirmed.** `WindowPeek.swift:124-179`, `AppWindows.swift:90-105`.

Minimize buttons always render but silently no-op without AX trust. Buttons are nested
inside window-selection buttons, which is unreliable for hit testing and accessibility.
Disable/hide unavailable actions, explain the permission, and separate the hit targets.

### M19. Reduce Motion/Transparency and contrast support are partial

**Confirmed; visual validation required.** `DockPanelController.swift:427-454`,
`DockTileView.swift:52-55`, `GlassBackground.swift`, system-monitor styles.

Only reveal/hide checks Reduce Motion; magnification, reorder, widget, and menu motion
continue. Reduce Transparency is read nonreactively and fallback still uses visual
effects instead of an explicit opaque high-contrast fill. Several monitor styles rely
on color alone. Propagate SwiftUI accessibility environment values, replace scaling
with static emphasis under Reduce Motion, and add labels/patterns for color-independent
meaning.

### M20. Settings ranges and display contents can be stale

**Confirmed.** `GeneralView.swift:36-69`, `DisplaysView.swift:55-64`,
`Preferences.swift:251-274`, `DockAnchor.swift`.

UI sliders expose smaller ranges than persisted clamps. A legal older value pins the
thumb and is silently rewritten on drag. `DisplaysView` is not invalidated on screen
changes and recomputes UUIDs during body evaluation. Use shared range constants and an
observable resolved-display snapshot.

### M21. Custom icon controls are offered for widgets that never render custom icons

**Confirmed.** `ItemsView.swift:69-84`, `DockModel.swift:193-215`,
`DockTileView.swift:116-147`.

Settings accepts and persists a custom path for built-in widgets, but widget views
always replace `tile.icon`. Either restrict the command to launchable/file/folder/link
tiles or deliberately support replacing widget content. Custom image files should also
be copied/bookmarked into Application Support instead of storing a fragile path.

### M22. Update comparison and download UX can falsely reassure or disappear

**Confirmed.** `UpdateChecker.swift:124-149,181-203`, `AboutView.swift`.

A malformed current or remote version reports "You're up to date". A manual check
during an in-flight background check no-ops. Download state is not visible, and failure
opens a browser without explanation. Report comparison errors, upgrade/queue manual
intent, and show download progress/result.

### M23. Empty docks render a blank interactive glass slab

**Confirmed.** `DockLayout.swift:25-44`, `DockController.swift:248-269`,
`ItemsView.swift:14-31`.

Empty content deliberately sizes as one tile and panels are still created. Show an
accessible "Drop apps here / Open Settings / Restore defaults" state, or suppress the
panel until a drag reaches its edge sensor.

### M24. Now Playing always opens Apple Music

**Confirmed.** `DockController.swift:472-473,745-750`.

Clicking a track sourced from Spotify or another player launches Music. Carry the
originating bundle identifier from MediaRemote when available and activate that app;
otherwise show a player chooser or no-op rather than opening the wrong app.

### M25. Weather uses `(0,0)` as "not configured"

**Confirmed.** `WeatherWidgetView.swift:30-32`, `Preferences.swift:78-83`.

Zero latitude/longitude is valid. Store an explicit configured flag and show a location
name or coordinate in tooltip/accessibility output.

### M26. Localization and locale-aware command parsing are absent

**Confirmed.** The project has no string catalog. `UnitConverter.swift`,
`CurrencyService.swift:79-92`, `ExpressionEvaluator.swift`, `ClockFormatter.swift`.

UI strings are English-only; calculator/conversion parsing assumes dot decimals and
English "in/to". Add a String Catalog, pseudolocalization/RTL coverage, accept locale
decimal separators while retaining `.` aliases, and localize date/meridiem output.

## Performance validation plan

The following order should find the most user-visible stutter quickly:

1. Trash containing 10,000-100,000 items, with several local/removable/network volumes.
   Signpost candidate discovery, state probe, rebuild, and panel relayout.
2. Fifty and one hundred tiles with 125 Hz and 1,000 Hz pointing devices. Record SwiftUI
   body evaluations, Core Animation FPS, allocations, and drag-reorder complexity.
3. Now Playing enabled for an hour with no media and active media. Count live dispatch
   sources/controllers and compare one versus three displays.
4. Window Peek against an app with 10-30 windows while rapidly crossing tiles and
   closing the dock. Track WindowServer CPU, cancellation, and retained images.
5. Ten minutes with every dock hidden for each live-widget combination. Use Energy Log
   to confirm which TimelineViews and samplers continue firing.
6. Apply presets and drag 100 files onto the dock. Count preference notifications,
   model publications, saves, frame recomputations, and shadow invalidations.
7. Wait past the five-minute icon TTL, then activate apps. Measure synchronous icon and
   accent work.
8. Sleep/wake with network graph, Trash on external storage, popovers open, and displays
   attached/detached. Verify no stale state, spikes, or off-screen panels.

## Missing or incomplete product features

- First-run consent/onboarding is promised in PLAN but absent.
- Spotlight-wide app discovery is promised; `AppIndex` scans fixed directories and one
  nested level.
- Minimized windows are excluded by `.optionOnScreenOnly`; Jetty cannot restore them.
- Automation status/guidance is absent from Permissions.
- Keyboard navigation covers Jetty Menu app rows, not the complete command/power
  surface, and the core dock has no navigator.
- PLAN mentions Escape hiding, a visible reveal sliver, configurable hide-after-launch,
  corrupt-store restore offers, and Dock-reappearance detection; these are not shipped
  or should be removed from current-product prose.
- Pomodoro completion is sound-only; notification delivery is missing.
- Settings lacks search, per-pane reset/undo, live preset/widget previews, and a
  searchable world-clock city picker.
- The window preview does not include minimized state, permission-disabled affordances,
  or exact-window confidence/error feedback.
- Badges/unread counts, taskbar/multi-row mode, and deeper Stage Manager handling remain
  legitimate later roadmap items rather than current bugs.

## Visual and interaction direction

- Build one authoritative `DockGeometry` snapshot. Every tile presentation frame,
  magnification displacement, glow, drag target, hit region, scroll offset, and popover
  anchor should come from it. Current duplicated math is the source of overlap and
  overflow drift.
- Treat edge and alignment as first-class in every overlay. Labels, indicators, drag
  removal, animations, popovers, and clock overhang should all move inward from the
  configured edge.
- Make state changes legible without becoming noisy. Trash should visibly accept a
  destructive drop; app launch should acknowledge; async failure should stay near the
  action; permission-gated controls should never look enabled.
- Preserve the distinctive retro/glass personality, but test it over bright, dark, and
  busy wallpaper with Increase Contrast, Differentiate Without Color, Reduce Motion,
  and Reduce Transparency.
- Avoid fixed tiny type such as the power-row labels. Use semantic text styles and one
  keyboard selection model across every visible menu entry.

## Delightful ideas

### Safe Dock handoff

On first run, leave Apple's Dock visible, ask the user to reveal Jetty once, then animate
a brief handoff and show a persistent Restore escape hatch. This turns the scariest
moment into a demonstration.

### Trash mood without background churn

Use the cached monitor state to show "Empty" or "Contains items" accessibly. After a
successful drop, give the can a short lid wobble or "gulp"; after Empty Trash, use the
existing poof. Optionally compute item count/size only on demand for a "Trash X-ray"
popover, never on every rebuild.

### Dock Navigator

A Carbon hotkey could open a compact keyable representation of the dock, using the
Jetty Menu focus-handoff pattern. Arrow through tiles, hear live values, press Return,
or invoke named context actions. This gives keyboard and VoiceOver parity without
changing the nonactivating core panel.

### Display topology editor

Show the user's actual monitor arrangement and let them drag a miniature Jetty pill to
an edge and slide it along that edge. It is clearer and faster than repeated edge,
alignment, offset, and inset controls.

### Undoable poof

Drag-out should show a floating tile and Remove zone, then a tiny "Removed - Undo"
bubble where the icon poofed. The icon can briefly reform if undone.

### Popover tether

A subtle glass stem/glow from tile to stack/peek plus a triangular hover corridor would
make child panels feel spatially attached and eliminate the awkward gap race.

### Glance expansion

Option-hover a widget to expand useful detail: battery time remaining, weather feels-
like/high/low, Pomodoro controls, or now-playing artwork. Mirror the same information in
VoiceOver custom actions.

### Where is my dock?

The menu-bar menu can pulse the configured reveal strip on every display and label its
edge. This is particularly useful after monitor rearrangement or a forgotten per-screen
override.

### Theme cards and contrast proofing

Render presets over light, dark, and busy sample wallpapers, warn when text/indicators
lose contrast, and export a small preview image beside the preset JSON for sharing.

### Day/night personalities

Use local sunrise/sunset math and existing weather coordinates to switch between two
user-selected presets. Keep it deterministic, local, and opt-in.

### Small bits of character

- Haptic alignment ticks as the pointer crosses tile centers, preference-gated.
- A Pomodoro progress ring in the menu-bar glyph while the dock is hidden.
- Scroll over an app to cycle windows; scroll over Pomodoro/world clock to adjust/cycle.
- Typing "boing" in Jetty Menu can send the existing Amiga ball across the dock once.
- A `jetty://` URL scheme can expose reveal/menu/preset/Pomodoro actions to Shortcuts.

## High-confidence implementation set

The following changes are small enough or isolated enough to implement without making
unreviewed product decisions. Each should be its own branch/PR, based on this review
commit, to minimize merge conflicts:

1. **Trash state pipeline:** bounded first-entry probing, no duplicate diagnostic scan,
   partial-path retry, revoke handling, dynamic monitor demand, and volume/wake refresh.
2. **Tile feedback/accessibility:** stronger Trash drop target and accepted/click pulse,
   default accessibility action, and hidden separator semantics.
3. **Edge inset:** stop stretching the visual panel back to the physical edge; also
   remove duplicate frame recomputation in the same panel-only change.
4. **Display reverse mapping:** make `key(for:)` return the collision-resolved key and
   expose observable display entries to Settings.
5. **System-stat timing:** use actual elapsed time, clear history after a long gap, and
   add pure regression tests. True CPU and 64-bit network sources remain separate work.
6. **Window Peek cancellation:** reuse the initial list, cancel stale tasks, and guard
   each capture generation.
7. **Now Playing lifecycle:** invalidate timeout generations, break the dispatch-source
   retain cycle, and cache the legacy MediaRemote lookup.
8. **Updater size baseline:** compare the downloaded asset to GitHub's advertised size,
   clean up mismatch files, and test the validator. Signature verification remains C1.
9. **Safe backup replacement:** create/verify a temporary backup before atomically
   replacing `.bak`.
10. **Lazy currency network access:** fetch rates only after a valid currency query,
    not every time Jetty Menu opens.
11. **Custom-icon scope:** stop offering a setting that built-in widget views ignore.

First-run onboarding, asynchronous command/error UI, neighbor-shifting magnification,
true CPU/network sampling, signed-update verification, and authoritative hit-testing
are all good work, but they require product decisions, credentials, broad architecture,
or live macOS validation and should remain in the durable backlog rather than being
landed blind.

## Required manual release matrix

- macOS 13 fallback and macOS 26 Liquid Glass, light/dark mode.
- Four edges, three alignments, inset 0/20/80, positive/negative offset, Apple Dock
  managed and visible.
- One, two, and three displays; stacked seams; attach/detach while Settings is open;
  sleep/wake; fullscreen and multiple Spaces.
- Trash empty/full on home and external volumes; mount/unmount; large Trash; hidden
  files; partial drop failure; denied Finder Automation.
- Magnification 1.0/1.5/2.5 with wide widgets, 250% clock, overflow scroll, reorder,
  drag-out, and file drop.
- VoiceOver, Full Keyboard Access, Reduce Motion, Reduce Transparency, Increase
  Contrast, Differentiate Without Color.
- Window names/thumbnails with no permissions, each permission independently granted,
  minimized windows, rapid hover, close during capture.
- Signed release smoke test: mount DMG, launch app, verify Team ID/entitlements/
  notarization/quarantine, perform update, restore Apple Dock after normal and forced
  termination.
