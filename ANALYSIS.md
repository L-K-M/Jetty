# Jetty analysis and roadmap

Updated 2026-07-10 from the static review in `sol.md`, reviewed at
`main @ a33cb74` and documented on main at `88d5ee3`.

This is the durable future-work document. Completed work is not repeated as open
backlog. Historical detail remains in `REVIEW.md`, `fable-is-awesome.md`, commit
history, and the review snapshot in `sol.md`.

The review environment was Linux with no Xcode or Swift installation. The changes
below received static review and `git diff --check`, but GitHub Actions did not execute
any step because the repository's Actions budget was exhausted. Build, unit, GUI, and
Instruments verification therefore remain required on macOS.

## Implemented in open PRs

These items have implementation branches and are not duplicated in the open backlog.
They are not considered shipped until their PR is reviewed, built on macOS, and merged.

| PR | Implemented scope | Residual work kept below |
|---|---|---|
| [#31](https://github.com/L-K-M/Jetty/pull/31) | Bounded Trash probing; partial-path retries; vnode revoke/replacement handling; lazy per-volume parent watches; mount/unmount/rename/wake refresh; no watcher without a Trash tile | Move all discovery/state I/O off main; asynchronous file moves and visible errors |
| [#32](https://github.com/L-K-M/Jetty/pull/32) | Strong Trash drop target; bounded click/drop pulse; Reduce Motion behavior; explicit default accessibility action; separators hidden from VoiceOver | Real success/partial-failure feedback; dynamic Trash/widget accessibility values; keyboard navigator |
| [#33](https://github.com/L-K-M/Jetty/pull/33) | Preserve the pure inset frame on every edge; stop drawing over a visible system Dock; remove duplicate panel frame calculation | Manual four-edge/Fitts-law verification; authoritative hit testing |
| [#34](https://github.com/L-K-M/Jetty/pull/34) | Collision-resolved display entries; exact reverse lookup; in-session key reservations; live Displays settings updates | Durable identity for indistinguishable duplicate/UUID-less displays across app relaunch |
| [#35](https://github.com/L-K-M/Jetty/pull/35) | Network rates use continuous real elapsed time; long-gap history reset; startup generation guard; tests | True CPU utilization; 64-bit network counters; utility-queue sampling and demand scoping |
| [#36](https://github.com/L-K-M/Jetty/pull/36) | Reuse initial Window Peek listing; cancel stale tasks; generation checks; cancellation between captures | Slower/event-driven cadence; smaller/visible-only captures; minimized windows and permission UX |
| [#37](https://github.com/L-K-M/Jetty/pull/37) | Reject late Now Playing callbacks; one-time legacy lookup; break poll-source retain cycle; controller cleanup | Long-lived notification-driven service; hidden-dock suspension; originating-player launch |
| [#38](https://github.com/L-K-M/Jetty/pull/38) | Reject downloaded assets whose byte count differs from GitHub metadata; cleanup and tests | Cryptographic signature, hash manifest, Team ID, notarization, trusted host policy |
| [#39](https://github.com/L-K-M/Jetty/pull/39) | Verify a temporary backup and atomically replace `.bak`; preserve primary/backup on failure; fault-injected test | Visible save/recovery/read-only state; off-main persistence |
| [#40](https://github.com/L-K-M/Jetty/pull/40) | Fetch currency rates only after valid ISO currency intent; loading/failed/provider-unsupported states; retry backoff | Provider disclosure/toggle; persisted source/date; explicit stale-rate indicator; HTTP metadata validation |
| [#41](https://github.com/L-K-M/Jetty/pull/41) | Offer/load custom icons only for tile kinds that render them; normalize legacy Trash aliases | Copy/bookmark custom images into Application Support; bounded/downsampled image storage |

## Priority summary

1. Establish a trustworthy signed/notarized release and authenticated update chain.
2. Add first-run consent before changing the global system Dock.
3. Finish the Trash action path: off-main state/moves, detailed results, and visible
   partial/total failure handling.
4. Fix invisible input interception and unify actual tile/glass geometry.
5. Implement neighbor-shifting magnification and profile pointer-frequency work.
6. Correct CPU/network data sources and scope hidden-widget work.
7. Make every modal/Automation action asynchronous, visible, and focus-safe.
8. Raise accessibility from labels to full information and operation parity.

## Critical

### C1. Authenticate updates end to end

`Jetty/Updates/UpdateDownloader.swift`, `UpdateChecker.swift`,
`GitHubRelease.swift`.

PR #38 catches truncation/substitution that changes byte count, but it does not identify
the publisher or contents. Required end state:

- Sign and notarize the app and disk image with Developer ID and hardened runtime.
- Publish a signed SHA-256 manifest or detached Ed25519 signature per asset.
- Validate signature/hash in an owner-only temporary directory before revealing it.
- Verify the extracted app's code signature, designated requirement, expected Team ID,
  entitlements, and notarization.
- Reject unexpected schemes, hosts, redirects, extensions, and content types.
- Keep quarantine; remove every instruction that recommends bypassing Gatekeeper.
- Test bad signatures, wrong Team ID, malformed/truncated/oversized assets, redirects,
  cleanup, and time-of-check/time-of-use behavior.

### C2. Replace the unsigned release workflow

`.github/workflows/release.yml`, `README.md:135-140`.

CI currently disables signing, ad-hoc signs, does not notarize, and publishes `xattr`
instructions. Make release jobs fail closed without credentials, then run `codesign
--verify --strict`, `spctl --assess`, notarization/stapling checks, and a mounted-DMG
smoke test before publication.

### C3. Pin the release supply chain

`.github/workflows/ci.yml`, `.github/workflows/release.yml`, `scripts/build.sh`,
`scripts/release.sh`.

Pin third-party Actions to full commit SHAs, pin Homebrew/tool versions and checksums,
verify the shared release-engine version/identity, and publish artifact hashes plus
provenance/SBOM.

## High priority

### H1. Finish the Trash pipeline off main and expose real outcomes

`Jetty/Apps/TrashLocations.swift`, `TrashMonitor.swift`, `AppLauncher.swift`,
`DockController.swift`, `DockModel.swift`.

PR #31 makes probing bounded and closes known watch-lifecycle holes. Remaining work:

- Move mounted-volume discovery and state probes to one serialized utility worker.
- Cache `empty/full/unknown`; publish only changes to the main actor.
- Avoid re-reading Trash on unrelated running-app model rebuilds.
- Batch and move `FileManager.trashItem` calls off main.
- Return moved URLs plus per-item errors, not just a count.
- Distinguish accepted, complete success, partial failure, and total failure in the UI.
- Run Empty Trash AppleScript off main and explain denied Finder Automation.
- Expose Empty/Contains items/Unavailable to VoiceOver.

Tests still needed: injected volume discovery/readers, event-to-scan count, missing and
unreadable directories, partial moves, permission failures, startup ordering, large
Trash, external volumes, and sleep/wake. Add direct watcher regression coverage for one
successful plus one failed open, per-path retry, lazy `.Trashes`/UID creation, `.revoke`,
mount/unmount, and vnode replacement/rearming; PR #31 implements these paths but does
not unit-test DispatchSource behavior.

### H2. Add first-run consent and a safe Dock handoff

`Preferences.swift:46-52`, `AppDelegate.swift:32-49`,
`DockController.swift:59-68`, `PLAN.md:482-494`.

Do not change `com.apple.dock` before explicit consent. Present Try Jetty / Keep Apple
Dock Visible / Quit, teach the reveal edge, require one successful reveal before hiding
Apple's Dock, and keep Restore System Dock visible. Persist onboarding separately from
the existence of `dock.json`.

### H3. Make panel hit testing match visible content

`DockPanelController.swift`, `DockView.swift`, `DockTileView.swift`.

Transparent magnification/clock headroom currently accepts input while visible clock
content can extend outside its base hit frame. The high-level drag sensor may create an
edge dead strip. Return nil outside actual glass and tile presentation frames; verify
whether drag registration works through mouse-transparent views or activate a lower
sensor only during drags.

Manual matrix: every edge, maximum clock zoom, auto-hide shown/hidden, scrollbars,
traffic lights, context menus, system Dock visible, and file drags.

### H4. Shift neighbors during magnification

`DockView.swift`, `DockTileView.swift`, `MagnificationCurve.swift`.

Tiles scale in place and overlap at default settings. Compute cumulative displacement
from the magnification curve so the row opens around the pointer. Drive centers,
presentation frames, z-order, glows, hit regions, drag targets, scroll state, and
popover anchors from one geometry snapshot.

### H5. Correct System Monitor data and execution context

`SystemStats.swift`, `LiveSystemStats.swift`.

PR #35 fixes elapsed-time spikes. Remaining correctness and performance work:

- Replace normalized one-minute load average with `HOST_CPU_LOAD_INFO` deltas.
- Replace 32-bit `if_data` counters with `NET_RT_IFLIST2` 64-bit counters.
- Reset baselines on interface replacement as well as long gaps.
- Read CPU/memory/network/battery on a utility queue.
- Publish one atomic sample, with equality gates.
- Track CPU/RAM, network, and battery demand separately.
- Use a 30-60 second battery-only cadence and pause expensive sampling while every
  panel is hidden, refreshing immediately on reveal.

### H6. Make background updates nonintrusive and visible

`UpdateChecker.swift`.

Automatic checks must not activate a modal alert over the user's work. Use a
notification or defer UI to the next user gesture. Centralize frontmost-app capture and
Finder fallback, show download progress/failure, and promote/queue a manual check that
arrives during background work.

### H7. Move AppleScript and destructive actions off main

`PowerCommands.swift`, `MenuCommand.swift`, `JettyMenuController.swift`,
`DockController.swift`.

Use one serial AppleEvent worker returning asynchronous `Result`. Keep or reopen visible
status, explain TCC denial with an Automation Settings link, and restore focus in every
success/cancel/error path. Apply the same focus coordinator to Dock Empty Trash and
update alerts.

### H8. Make Lock Screen truthful and fail closed

`PowerCommands.swift:107-136`, `Settings/MenuView.swift`, tests/docs.

Inspect `SACLockScreenImmediate`'s return value. Missing symbol or non-success must be a
visible failure. A screen-saver fallback must be labeled Start Screen Saver because the
user's password delay may leave the session unlocked. Update stale settings copy/tests.

### H9. Complete accessibility parity

`DockTileView.swift`, widget views, Settings custom controls.

PR #32 adds default actions and hides separators. Remaining work:

- Expose dynamic clock, Trash, battery, weather, CPU/RAM/network, now-playing, world
  clock, and Pomodoro values and hints.
- Add named context actions where meaningful.
- Give `AngleDial` adjustable actions and numeric degree output.
- Label/select glyph buttons and give sliders unit-bearing values.
- Add a Carbon-hotkey-driven keyable Dock Navigator for arrows, Return, and context
  actions without changing the nonactivating core panel.
- Audit VoiceOver, Full Keyboard Access, and Accessibility Inspector on macOS.

### H10. Finish durable display identity

`DisplayRegistry.swift`, `DisplaysView.swift`.

PR #34 fixes exact current-session reverse lookup and live settings refresh. Persisted
placement for UUID-less or truly duplicate-UUID hardware is still not guaranteed across
app relaunch. Investigate stable EDID/vendor/product/serial characteristics available
without private APIs, preserve disconnected stored displays with Forget controls, and
document session-only fallback where no durable discriminator exists.

## Performance and architecture

### P1. Coalesce preference invalidation

`Preferences.swift`, `DockController.swift`, dock/widget views.

One object publishes dozens of unrelated fields to every dock and tile. Split immutable
render domains or pass small equatable configurations, batch preset application, and
cancel/coalesce controller preference work. Persist continuous slider changes on a
short debounce or editing completion where safe.

### P2. Publish one model snapshot and batch store changes

`DockModel.swift`, `DockController.swift`, `DockStore.swift`.

Slots and tiles publish separately; store changes queue rebuild plus reconciliation;
bulk pinning mutates once per URL. Publish one model snapshot, add store transactions
such as `addItems`, diff geometry before relayout, and coalesce to one save/rebuild/
reconciliation per user operation. PR #33 already removes one duplicate frame call.

### P3. Reduce pointer-frequency work

`DockView.swift`.

Cache tile centers/extents until structure changes, calculate scales and the reorder
target once per event, pass an offset map to slots, and coalesce raw pointer movement to
display cadence while preserving hard-edge intent. Current drag target calculation is
roughly quadratic in slot count.

### P4. Suspend hidden work and unused mouse monitoring

`DockController.swift`, `EdgeHoverMonitor.swift`, live widgets.

Publish panel visibility through a shared coordinator. Suspend expensive shared
services when every dock is hidden and refresh on reveal. Start global/local mouse
monitoring only when some panel uses auto-hide plus edge hover; route to the relevant
screen and coalesce high-rate events.

### P5. Fix icon-cache cliffs and unbounded caches

`DockModel.swift`, `IconCache.swift`, `TileAccent.swift`, `JettyMenuModel.swift`,
`ItemsView.swift`.

Use stale-while-revalidate instead of synchronized five-minute expiry, cost-limited
`NSCache` for menu/accent images, icon-identity/version keys, off-main accent extraction,
and downsampled custom images. Cache Settings row icons. PR #41 prevents pointless
widget custom-image loads but not general image cost.

### P6. Finish Window Peek efficiency

`WindowPeek.swift`, `AppWindows.swift`.

PR #36 cancels obsolete generations. Next steps: topology refresh slower or event-
driven, capture only visible thumbnails near displayed pixel size, publish one snapshot,
avoid AX title scans when CG data is present, and pause when the child panel is hidden.

### P7. Make Now Playing notification-driven

`NowPlayingService.swift`, `MediaRemoteBridge.m`, `NowPlayingWidgetView.swift`.

PR #37 bounds known leaks/races. Replace fresh-controller polling with one long-lived
controller or MediaRemote change notifications, add a freshness gate, centralize cadence
across displays, and suspend while all docks are hidden. Keep private API use isolated,
opt-in, and fail-closed.

### P8. Cancel folder-stack work and report state

`FolderStack.swift`, `FolderStackController.swift`.

Store a cancellable task/work item and check during enumeration, metadata, sorting, and
icon loading. Return error/truncated state instead of conflating failures and empty
folders; show Couldn't read and Showing first 128. Optionally watch the open folder.

### P9. Remove duplicate Jetty Menu work

`AppIndex.swift`, `JettyMenuModel.swift`, `RecentAppsStore.swift`.

Avoid the initial double app scan, cancel/coalesce reloads, query recents only for an
empty query, publish one menu state, cache formatters, and resolve result icons
asynchronously. Add Spotlight-wide indexing as described under missing features.

### P10. Move persistence off main and surface errors

`DockStore.swift`.

Snapshot the document and perform encode/backup/write on one serial I/O queue, retaining
a synchronous termination flush. Expose save status/errors. PR #39 makes replacement
safe but still performs I/O on main.

## Correctness and UX

### U1. Make bookmark-backed actions consistent

`DockController.swift`, `BookmarkResolver.swift`.

Normal click refreshes a bookmark, but drag-to-open and Show in Finder can use stale
URLs. Route every explicit action through one resolved URL. Hover eligibility should
use cheap metadata; resolve after dwell off-main with `withoutUI`/`withoutMounting`, and
allow mounting only after explicit user action.

### U2. Report launch success before recording recents

`AppLauncher.swift`, `DockController.swift`, `JettyMenuController.swift`.

Use `NSWorkspace` completion results, record recents only on success, show launch/open
errors, provide a brief nonintrusive positive launch acknowledgement, and retain exact
URL/PID identity when duplicate app copies share a bundle ID.

### U3. Validate and report hotkey registration

`HotkeyRecorder.swift`, `DockController.swift`, `CarbonHotkey.swift`.

Suspend current registrations while recording, reject duplicate Jetty assignments,
and show Carbon/OS-owned registration failures inline rather than displaying a shortcut
that does nothing.

### U4. Model every launch-at-login status

`Preferences.swift`, `GeneralView.swift`.

Represent `.enabled`, `.requiresApproval`, `.notRegistered`, and failure states. Offer
the Login Items settings link, unregister pending registration when toggled off, and
avoid unexplained toggle snapback.

### U5. Surface store recovery and read-only mode

`DockStore.swift`, Settings.

Expose whether primary, backup, or defaults loaded. Warn when both primary/backup are
corrupt, disable or clearly mark mutations in future-version read-only mode, and offer
backup export/restore. Show persistent save failure. PR #39 protects backup replacement
but does not expose state.

### U6. Fix edge-aware labels

`DockTileView.swift`, `DockPanelController.swift`.

Hover labels always move upward and can be clipped. Use edge-aware placement with
reserved headroom or a separate lightweight label panel anchored to presentation
frames. Add a dwell to avoid flicker.

### U7. Make drag-out visible, outward-only, and undoable

`DockView.swift`, `DockController.swift`.

Render an unclipped floating ghost, show a Remove zone/label when crossing the
threshold, count only movement away from the configured edge, and offer a brief Undo
toast after poof. Define an overflow-mode gesture that does not fight scrolling.

### U8. Coordinate dock and child-popover lifetime

`DockPanelController.swift`, `DockController.swift`, stack/peek controllers.

Keep the dock revealed while a context menu, folder stack, Window Peek, or drag is open
or hovered. Add a triangular hover corridor and optional subtle visual tether.

### U9. Make Window Peek permission-aware and include minimized windows

`WindowPeek.swift`, `AppWindows.swift`.

Do not render enabled minimize controls without Accessibility. Remove nested buttons,
show permission guidance, inspect AX return values, activate then raise the exact
window, expose exact-window matching confidence and operation errors, and merge AX
windows so minimized windows appear with restore/unminimize state.

### U10. Fully honor accessibility display settings and contrast

`GlassBackground.swift`, dock/menu/widget views.

Propagate Reduce Motion/Transparency, Increase Contrast, and Differentiate Without
Color. Under Reduce Motion replace scaling with a static halo/label. Under Reduce
Transparency use an opaque semantic surface. Add labels/line styles beyond color and
test themes over bright, dark, and busy wallpaper.

### U11. Use one source of truth for Settings ranges

`GeneralView.swift`, `DisplaysView.swift`, `Preferences.swift`, `DockAnchor.swift`.

Current UI ranges are smaller than persisted clamps. Publish model constants and use
them everywhere so older/legal values do not show pinned thumbs or silently rewrite on
first drag. PR #34 handles display-list freshness only.

### U12. Make custom images durable

`ItemsView.swift`, store.

PR #41 removes unsupported controls. For supported tiles, copy/downsample the selected
image into `Application Support/Jetty/icons/<item-id>` or persist a bookmark, clean it on
clear/removal, and cap decoded pixel cost.

### U13. Fix update comparison and manual-check behavior

`UpdateChecker.swift`, `AboutView.swift`.

Malformed versions must report a comparison error, not You're up to date. A manual
check during background work should upgrade/queue user intent. Show progress, saved
path, and explained failure rather than silently opening a browser.

### U14. Provide an empty-dock recovery surface

`DockLayout.swift`, `DockController.swift`, `ItemsView.swift`.

Do not reveal a blank glass slab. Show Drop apps here / Open Settings / Restore defaults,
or suppress the visual panel until the edge sensor receives a drag.

### U15. Open the originating now-playing app

`DockController.swift`, MediaRemote parsing.

Carry player bundle identity when available and activate it. Do not always launch Apple
Music for Spotify/other-player content; provide a chooser or no-op fallback.

### U16. Store explicit weather configuration

`WeatherWidgetView.swift`, `Preferences.swift`.

`(0,0)` is a valid coordinate. Add a configured flag/migration and expose location name
or coordinates in tooltip and accessibility value.

### U17. Localize UI and command parsing

Add a String Catalog, pseudolocalization, and RTL testing. Parse locale decimal
separators while retaining `.` aliases; localize `in/to`, enum labels, dates, and
meridiem output.

### U18. Make currency source and age transparent

`CurrencyService.swift`, Menu settings/view.

PR #40 makes access intent-driven. Add provider disclosure/opt-out, HTTP status and
payload-date validation, persisted source/date, and stale-rate labeling. Never silently
present financial output of unknown age.

## Missing and incomplete features

- Spotlight/`NSMetadataQuery` app discovery beyond fixed directories and one nested
  level; merge by bundle ID/path and show indexing state.
- Minimized-window listing and restore through the opt-in AX path.
- Automation status and recovery guidance in Permissions.
- One keyboard selection model spanning app results, calculations/conversions,
  commands, web search, and power actions; typed power commands and `Command-Return`
  web search. Replace fixed tiny power-row labels with semantic text styles.
- Pomodoro completion notification in addition to sound.
- Settings search, per-pane reset/undo, live preset/widget preview, searchable grouped
  world-clock city picker, and Add/Remove tile actions in Widgets.
- PLAN-described Escape hide, visible reveal sliver, configurable hide-after-launch,
  corrupt-store restore offer, and system-Dock-reappearance detection. Implement them
  or correct PLAN so they are not current promises.
- Badges/unread counts, taskbar/multi-row mode, and deeper Stage Manager behavior remain
  later roadmap items, not current regressions.

## Profiling plan

1. Trash with 10,000-100,000 items and local/removable/network volumes. Signpost
   discovery, state probe, model rebuild, and panel relayout.
2. Twenty, fifty, and one hundred tiles with 125 Hz and 1,000 Hz pointers. Record body
   evaluations, Core Animation FPS, allocations, drag complexity, and animation commits.
3. Now Playing for an hour with no media and active media, one and three displays.
   Count live dispatch sources/controllers and hidden-dock callbacks.
4. Window Peek on an app with 10-30 windows while rapidly crossing tiles and closing.
   Track WindowServer CPU, cancellation, image memory, and post-close publications.
5. Ten hidden minutes for every live-widget combination using Energy Log.
6. Preset application and a 100-file dock drop. Count preference notifications, model
   publications, saves, frame updates, and shadow invalidations.
7. Wait through icon-cache expiry, then activate apps and measure icon/accent work.
8. Sleep/wake with network graph, external Trash, child popovers, and display changes.

## Manual release matrix

- macOS 13 fallback and macOS 26 Liquid Glass; light and dark mode.
- Four edges, three alignments, inset 0/20/80, both offset directions, Apple Dock
  managed and visible.
- One/two/three displays, stacked seams, attach/detach while Settings is open, sleep/
  wake, fullscreen, Spaces, and display identity collisions where reproducible.
- Trash home/external empty/full, mount/unmount, hidden files, large contents, partial
  drop failure, denied Finder Automation, and vnode replacement after Empty Trash.
- Magnification 1.0/1.5/2.5 with wide widgets, 250% clock, overflow, reorder, drag-out,
  labels, popovers, and file drop.
- VoiceOver, Full Keyboard Access, Reduce Motion, Reduce Transparency, Increase
  Contrast, Differentiate Without Color.
- Window names/thumbnails with no permissions and each permission independently
  granted; minimized windows; rapid hover; close during capture.
- Signed release: mount DMG, inspect app contents, verify Team ID/entitlements/
  notarization/quarantine, update, normal quit restore, and force-termination recovery.

## Delight roadmap

### Highest value

- **Safe Dock handoff:** turn onboarding into a reveal rehearsal before hiding Apple's
  Dock.
- **Neighbor-shifting magnification:** the biggest perceived-quality improvement.
- **Dock Navigator:** keyboard/VoiceOver parity using the Jetty Menu focus handoff.
- **Display topology editor:** drag a miniature dock around the user's real monitor map.
- **Undoable poof:** floating removal ghost, Remove cue, and Removed - Undo bubble.
- **Popover tether:** subtle glass stem/glow plus hover corridor.

### Trash personality

- A restrained lid wobble or "gulp" only after confirmed success; static ring under
  Reduce Motion.
- Poof after confirmed Empty Trash.
- Trash X-ray count/size computed only on demand; Trash events invalidate its cache,
  and model rebuilds/events never eagerly recompute it.

### Glanceable widgets

- Option-hover expansion for battery time remaining, weather feels-like/high/low,
  Pomodoro controls, and artwork.
- Pomodoro progress ring in the menu-bar glyph.
- Multi-city world-clock carousel with day/night shading.
- Sunrise/sunset, moon phase, AQI/UV, disk space, Time Machine, and next-calendar-event
  tiles, with permissions isolated and opt-in.

### Personalization and automation

- Theme cards previewed over light/dark/busy wallpaper with contrast warnings, with an
  exported preview image alongside preset JSON for sharing.
- Opt-in sunrise/sunset switching between two presets.
- `jetty://` reveal/menu/preset/Pomodoro URLs for Shortcuts and automation.
- Per-tile launch hotkeys and scroll gestures for windows/timer/world-clock cycling.
- Per-display appearance personalities.
- Script-fed badge/unread overlays with a simple local protocol.

### Small character moments

- Haptic alignment ticks as hover crosses tile centers, preference-gated.
- Where is my dock? pulses and labels configured reveal edges on every display.
- Dock breathing once after wake/display recovery.
- Typing `boing` in Jetty Menu sends the existing Amiga ball across the dock once.
- Accessible Color Time narration such as "approximately three o'clock."

## Architectural guardrails

- Do not reserve screen space or move other applications' windows.
- Do not add global key monitoring or event taps to the core.
- Keep dock and ordinary child panels nonactivating; only Jetty Menu performs its
  deliberate focus handoff.
- Keep Liquid Glass gated to macOS 26 with an accessible fallback.
- Persist display identity plus edge/alignment/offset/inset, never raw window frames.
- Keep optional private APIs isolated, opt-in, weak/dynamic, and fail-closed.
- Never use killing/injecting the system Dock as an ongoing strategy; preserve Restore.
