# Jetty — Code Review

A thorough, living review of Jetty covering bugs, security, performance,
visual/layout, UX, missing features, and delight-level ideas. Findings are
prioritized by severity with concrete fixes and `file:line` references.

The codebase is genuinely high quality — the pure/UI separation is clean, the
"no permission for the core dock" promise is honored, lossy Codable decoding is
defensive, and the `.bak`-guarded store is the right pattern. Most open findings
are polish, robustness, and feature-completeness rather than structural
problems. The exceptions are the **update-security items (C1–C3)**, which are
the top priority.

---

## Consolidation & status update (2026-07-02)

This file is the **single consolidated review + roadmap** for Jetty. It folds in:

- the earliest *GPT-is-awesome* review (BUG/ISSUE history — all resolved — and its
  delight ideas; see [Earlier review history](#earlier-review-history)); and
- the later *Fable review* (`fable-is-awesome.md`, 2026-07-02), whose findings and
  ideas have now been merged here. Like `GPT-is-awesome.md` before it,
  `fable-is-awesome.md` has been **removed** — this file is the live record.

`PLAN.md` stays the design/feasibility record and points here for live status.

### Implemented and removed (2026-07-02)

Twenty fix branches from the Fable review landed on `main` together. The items
they resolved have been **removed** from the lists below; the residual work from
partially-resolved items has been reworded in place. Verified against the merged
code (`main @ fd579a8`).

**Backlog items fully resolved:**

- **High:** H2 (Return copies a calc/conversion/currency result instead of
  leaking it to a web search), H4 (diacritic/width-insensitive app search),
  H12 (Pomodoro survives sleep + persists across relaunch), H15 (weather surfaces
  errors instead of an eternal spinner), H22 (Lock Screen actually locks via
  loginwindow), H25 (`AppIndex.reload()` guards racing scans with a generation
  token).
- **Medium:** M10 (selected-row contrast from tint luminance), M11 (hover-to-select
  + always-on web-search row), M17 (menu empty state), M18 (selection preserved by
  id), M25 (PermissionsView poll relaxed to 5 s), M29 (clock cadence minute-aligned),
  M30 (battery level glyph + low-battery emphasis).
- **Low:** L6 (`AppSearch.score` folds the query once), L36 (the MediaRemote
  controller-path fail-closed gap — C4 — is closed).
- **Closed as invalid/moot:** L3 (`releaseNotes()` truncation strides by `Character`
  = grapheme cluster; it cannot split one), M37 (its premise — "used on every tile
  click" — is stale; that path is dead code, and the live click path already
  refreshes bookmarks through `DockStore`. The remaining action is deleting the dead
  code, tracked as **F-L14** below).

**Partially resolved — residual work reworded in place:** H14 (formatter caching
landed; a minor `WorldClock` `TimeZone` recompute remains — see Low), H16 (shared
`CIContext` landed; two unbounded caches remain), M15 (the app-global key-swallow
bug is fixed; the typed/`⌘1–9` enhancement folds into M16), M33 (label overflow
fixed; completion notification remains), M21/L14 (small a11y / fallback nits still
open).

**New fixes from the Fable review** (not previously in this backlog) — auto-hide-off
now reveals the dock, Settings "Restore System Dock" sticks, imported presets are
angle-clamped and tolerate unknown enums (and round-trip `accentGlow`), the menu
`Return`/keyword-match no longer hijacks real app names, a single-instance guard,
prerelease tags no longer ship as "latest", CI/release hardening (tests-on-release,
least-privilege token, timeouts, PR-only cancellation), calculator `-2^2`/Unicode
minus, Finder in app search, unique tile ids for duplicate pins, IME-safe menu keys,
menu focus hand-off, weather unit flip-back, live Pomodoro length changes, weather
coord clamping, `HotkeyRecorder` honoring `.disabled`, an inert-tint caption, the
`⌘,`/`⌘W` main-menu items, secure restorable state, an Animation-duration slider,
per-render Settings work cached, and the README/AGENTS/entitlements truth fixes.
(Their former Fable ids are retained in commit history.)

The remaining Fable findings that were **not** implemented — deliberately deferred
(needs a live GUI, a compiler, or a product decision) or simply unstarted — are
folded into the ranked lists below with their `F-*` ids so nothing open is lost.
Notably there was **no sampler-accuracy change**, so the network-rate and
sampler-publish issues (**F-M6 / F-P3**) remain open.

One known issue: a `layoutSubtreeIfNeeded` recursion warning in the console from the
tile-scroll `GeometryReader` (horizontal overflow-scroll). No user-visible breakage
observed, but worth resolving.

---

## Table of contents

- [Critical](#critical)
- [High](#high)
- [Medium](#medium)
- [Low / polish](#low--polish)
- [Delightful feature ideas](#delightful-feature-ideas)
- [What's done well](#whats-done-well)
- [Roadmap & open product items](#roadmap--open-product-items)
- [Earlier review history](#earlier-review-history)

---

## Critical

### C1. Self-updater performs no verification — no checksum, signature, or code-signature check
**`Jetty/Updates/UpdateDownloader.swift:10-20`** · SECURITY

`downloadToDownloads` downloads the asset over HTTPS, checks the HTTP status, and
moves it into `~/Downloads`. That's it. There is:

- **No SHA-256 / size check** — `GitHubRelease.Asset` even decodes a `size` field
  that is never compared against the downloaded bytes.
- **No detached signature verification** of any kind.
- **No `SecStaticCodeCheckValidity`** on the downloaded `.app` (no Team-ID or
  notarization check).
- **No certificate pinning** of `api.github.com` / `objects.githubusercontent.com`
  — the updater trusts whatever root CAs the system ships.
- **No TOCTOU hardening** — the file lands in the world-traversable
  `~/Downloads` before being handed to Finder.

Threat model: a MITM (compromised/enterprise CA, hostile network), or a
compromised GitHub release (leaked token, hijacked maintainer, typosquatted fork
the user is tricked into configuring as `owner`/`repo`) drops arbitrary code.
Combined with **C2**, there's nothing to verify against.

**Fix (in order of impact):**
1. Ship an Ed25519 public key in the bundle. Publish `<asset>.sig` per release.
   Verify the signature *before* revealing in Finder.
2. As a near-free baseline: compare downloaded byte count to `asset.size` and
   recompute SHA-256 against a signed manifest.
3. After extraction: `SecStaticCodeCheckValidity` + assert the Team ID matches
   the expected value and that it's notarized (`spctl --assess`).
4. Pin GitHub's SPKI via `urlSession(_:didReceive:completionHandler:)`.
5. Verify in a `0700` owner-only temp dir; only move to `~/Downloads` once good.

### C2. Releases ship unsigned + un-notarized, with `xattr -dr quarantine` as the documented install path
**`.github/workflows/release.yml`** · SECURITY

The release workflow builds with `CODE_SIGNING_ALLOWED=NO`, ad-hoc signs with
`codesign --force --deep --sign -`, and tells users to run
`xattr -dr com.apple.quarantine` to bypass Gatekeeper. For an app that runs at
login (`SMAppService`), holds Apple-Events/Automation permission, hides and
re-asserts the system Dock, and reads the user's Applications folder, this is a
serious risk posture: any attacker who can substitute a binary gets an
auto-launched, Automation-privileged foothold with no Gatekeeper speed-bump — and
C1 means there's no verification to stop them.

**Fix:** introduce a Developer ID in CI via secrets, sign with
`codesign --force --options runtime --entitlements … --sign "Developer ID Application: …"`,
run `xcrun notarytool submit … --wait`, staple with `xcrun stapler staple`.
Remove the `xattr` advice. Then wire C1's verifier to assert the Team ID.

### C3. CI uses third-party actions pinned to floating tags
**`.github/workflows/release.yml`, `ci.yml`** · SECURITY

`softprops/action-gh-release@v2`, `actions/checkout@v4`, and
`maxim-lobanov/setup-xcode@v1` are moving tags. If any of those repos is
compromised (high-value targets), an attacker ships a new `v2.x`/`v4`/`v1` that
exfiltrates `GITHUB_TOKEN` and silently swaps the `.dmg` on every release.
Combined with C1+C2, that's a complete silent-compromise chain. (The 2026-07-02
CI hardening added least-privilege token scopes, timeouts, tests-on-release, and
PR-only cancellation — but the actions themselves are still unpinned.)

**Fix:** pin every third-party action to a SHA digest
(`softprops/action-gh-release@<full-sha> # v2.x.y`).

---

## High

### H7. MediaRemote controller path polls a fresh private controller every 5 s
**`Jetty/Widgets/NowPlayingWidgetView.swift:12` + `MediaRemote/MediaRemoteBridge.m:77-79,89-144`** · PERFORMANCE

Each `refresh()` allocates a fresh `MRNowPlayingController`, calls
`beginLoadingUpdates`, polls, then `endLoadingUpdates` and releases. Heaviest
private-API call in the app, at ~5 Hz for as long as the tile is on screen — even
when playback state hasn't changed. The legacy `dlopen` handle is also never
`dlclose`d and `dlsym` is re-resolved every call.

**Fix (incremental):** back off to 10–15 s when paused/idle. **Fix (proper):**
register for now-playing change notifications
(`MRMediaRemoteRegisterForNowPlayingNotifications` + `NotificationCenter`) and
stop polling. Cache the controller and the function pointers (`dispatch_once`).

### H8. Magnified tiles overlap their neighbors (no squish / neighbor-shift)
**`Jetty/Dock/DockTileView.swift:57,227-234` + `DockView.swift:324-388`** · VISUAL

Each tile does `.scaleEffect(scale, anchor: scaleAnchor)` where the anchor is the
edge-facing side, so a tile widens symmetrically along the dock axis. With
`maxScale = 1.5` and `base = 52`, that's +13 pt on each side — past the 8-pt
default spacing — so neighbouring icons visibly clip at the bump's peak. The real
macOS Dock shifts the whole row apart by the integral of the magnification curve.

**Fix:** offset each tile by a neighbor-aware shift (compute the cumulative
magnification from the strip start to the tile center, mirroring `tileCenters`).
The single biggest "feels like the real Dock" win.

### H9. Edge drag-sensor panel swallows clicks/hover at the screen edge
**`Jetty/Dock/DockPanelController.swift:435-458`** · BUG/UX

When auto-hide + edge-hover are on, `updateDragSensor()` installs a 6-pt `NSPanel`
at `.popUpMenu − 1` hugging the visible-frame edge. It registers for file drags
but never sets `ignoresMouseEvents = true`, so it intercepts ordinary
mouse-down/mouse-moved in its 6-pt strip. On a top-edge dock that overlaps
traffic-light buttons; on left/right edges it eats scrollbar arrows and
edge-swipe hotspots. Measurable dead zones at every targeted screen edge.

**Fix:** set `sensorPanel.ignoresMouseEvents = true` (drag tracking is independent
of `ignoresMouseEvents` in AppKit — verify empirically). At minimum drop the
window level to just above app windows instead of `.popUpMenu − 1`.

### H13. Network byte counters are 32-bit and wrap at 4 GB
**`Jetty/Widgets/SystemStats.swift:98-118`** · BUG

`getifaddrs`/`AF_LINK`'s `ifa_data` points at `struct if_data` whose
`ifi_ibytes`/`ifi_obytes` are `u_int32_t` (4 GB). On a gigabit link a sustained
download wraps in ~32 s. The wrap is caught by `LiveSystemStats.throughput`
(current < previous → 0), so the live graph shows a periodic dip to zero during
every large transfer — visually broken for what should be the marquee case. The
`UInt64(...)` cast widens an already-wrapped 32-bit value; it doesn't prevent the
wrap.

**Fix:** switch to `sysctl` with `NET_RT_IFLIST2`, which returns
`struct if_msghdr2` with 64-bit counters. Matches `netstat -i`/Activity Monitor.

### H16. Icon caches grow unboundedly for app lifetime (CIContext now shared)
**`Jetty/Menu/JettyMenuModel.swift:105` + `Jetty/Common/TileAccent.swift:10`** · PERFORMANCE/MEMORY

The expensive-`CIContext`-per-call half of this is fixed (`TileAccent` now shares
one `static let` context). Still open: `JettyMenuModel.iconCache: [String: NSImage]`
accumulates a full-res `NSImage` (~1 MB each) for every app ever seen, no eviction;
and `TileAccent.cache` is a never-cleared mutable static. Over a long lifetime both
leak meaningfully. See also **F-P1** (the icon cache's *other* cache — the bounded
`LRUImageCacheByKey` in `DockModel` — has a synchronized-expiry storm).

**Fix:** swap for `NSCache` (auto-evicts under pressure) or the existing
`LRUImageCache`/`LRUImageCacheByKey`. Add `clearCache()` and call from `DockStore`
on item changes.

### H20. WindowPeek's 1-second screen-capture timer is expensive
**`Jetty/Windows/WindowPeek.swift:29`** · PERFORMANCE

`Timer(timeInterval: 1.0, repeats: true)` captures every visible window of the
hovered app every second while the popover is up. `SCShareableContent.current` +
an `SCScreenshotManager.captureImage` per window is real CPU/GPU work, running
even when nothing on screen changed. (`WindowLister.windows(forPID:)` is also
called twice per peek show — `WindowPeekController.swift:30` + `WindowPeek.swift:47`.)

**Fix:** raise to ~3 s, pause when `model.thumbnails` would be unchanged
(compare window-list bounds), or invalidate on `NSWorkspace.didActivateApplication`.
Pass the pre-fetched window list into `model.load` to avoid the double fetch.

### H21. Power commands / automation silently fail when permission is denied
**`Jetty/Menu/PowerCommands.swift:79-85` + `Jetty/Menu/JettyMenuController.swift:112-124`** · UX/SECURITY

When the user denies Automation permission, `NSAppleScript.executeAndReturnError`
returns an error and the only feedback is `NSLog(...)`. The menu has already
closed, so the user gets **no** indication their Sleep / Toggle Dark Mode didn't
work — and no path to retry. The TCC prompt may pop up *after* the menu is gone,
leaving the user confused. (Pairs with **F-M4**: the same AppleScript runs
synchronously on the main thread.)

**Fix:** don't `close()` until the script resolves. On error, surface an in-menu
banner ("Automation permission denied — open System Settings?") with a deep link
to `x-apple.systempreferences:com.apple.preference.security?Privacy_Automation`.

### F-H3. "Edge inset" is a visual no-op on 3 of 4 edges — and can draw Jetty over the live system Dock
**`Jetty/Dock/DockPanelController.swift:349-364` + `Jetty/Dock/DockView.swift:39-43`** · BUG/VISUAL · needs-device-verify

`DockLayout.revealedFrame` lifts the frame by `inset`, but `recomputeFrames()`
then stretches the panel back to the physical edge (every edge except `.top`), and
`DockView` pins the glass strip to the edge-facing side of the panel. So the strip
renders at the physical screen edge regardless of inset: the "Edge inset" sliders
(General + Displays) and the documented "floating island" look do nothing on
bottom/left/right. Worse: when the system Dock is visible (`manageSystemDock` off,
or after Restore while Jetty runs), the stretch equals the Dock's height and Jetty's
strip is drawn over the live Dock at `.popUpMenu` level. The stretch only ever fires
in those two cases — with the Dock hidden and inset 0, the gap is 0 — so it has no
beneficial case on those edges.

**Fix:** guard the stretch to `anchor.inset == 0 && gap <= small`, or keep the
stretched panel but convert the inset into edge-side content padding so hard-edge
clicks still land on icons while the strip floats.

---

## Medium

### M1. App-icon resolution on the main thread on every running-app change
**`Jetty/Dock/DockModel.swift:72-85, 185-189` + `DockController.swift:183-188`** · PERFORMANCE

`rebuild` is called on every launch/terminate/activate/deactivate/hide/unhide and
loops all tiles calling `icon(for:)` — on a cache miss `NSWorkspace.shared.icon(forFile:)`
is a synchronously blocking, LaunchServices-touching call. `relayoutPanels()`
also runs on every activate/deactivate even though panel frames only depend on
tile kinds/counts, which don't change on a plain focus flip.

**Fix:** resolve first-time icons on a background queue and merge back to main.
Diff slot/tile structure and skip `relayoutPanels()` when only `isRunning`/
`isActive` flags changed (extend the `prefSig` idea to model changes).

### M3. `panel.invalidateShadow()` runs on every non-animated relayout
**`Jetty/Dock/DockPanelController.swift:410`** · PERFORMANCE

`applyRevealState(animated:)` is called from `layoutForCurrentState()` on every
`relayoutPanels()` → which fires on every running-app notification. Each call
ends with `panel.invalidateShadow()`, forcing shadow recomputation for a
transparent, hasShadow panel. During cmd-tab storms, dozens of shadow
recomputations/sec per panel.

**Fix:** only invalidate when the reveal/hidden state or frame actually changed.

### M4. Live stats timer and widget TimelineViews keep running while the dock is hidden
**`Jetty/Dock/DockController.swift:183-188` + per-widget `TimelineView`s** · PERFORMANCE

`updateLiveStats()` gates the sampler on `!panels.isEmpty` but not on whether any
panel is *revealed*. The per-widget `TimelineView`s (Clock, WorldClock, Weather,
NowPlaying) also keep firing while the panel is hidden via a layer transform —
~95% of the time for an auto-hiding dock. Most of the timer / CPU / MediaRemote
work is wasted.

**Fix:** gate on `panels.values.contains { $0.isRevealed }`. Expose `isRevealed`
to `DockView` and swap/tear down the periodic schedules while hidden. At minimum
make the NowPlaying poll a no-op while hidden.

### M5. All sampler syscalls run on the main thread every 2 s
**`Jetty/Widgets/LiveSystemStats.swift:81-93`** · PERFORMANCE

`Timer` on `RunLoop.main`; `sample()` synchronously calls `getloadavg`,
`host_statistics64`, `getifaddrs`, and (every 15th tick) `IOPSCopyPowerSourcesInfo`
on the main thread — `getifaddrs` can block briefly. This is exactly the kind of
thing that produces micro-hitches while the dock animates.

**Fix:** sample on `DispatchQueue.global(qos: .utility)`, hop to main only to
assign `@Published` properties.

### M7. Edge-hover monitor fires on every mouse move with no throttle
**`Jetty/Dock/EdgeHoverMonitor.swift:18-28` + `DockController.swift:65-67`** · PERFORMANCE

The global + local monitor pair calls `onMove?(NSEvent.mouseLocation)` for every
`.mouseMoved`/`.leftMouseDragged`/`.rightMouseDragged` system-wide, then
dispatches to `panels.values.forEach`. On a 120 Hz trackpad with 3 panels that's
~360 invocations/sec of `handleMouseMoved`, each doing several `NSMouseInRect`
calls, all on the main thread, unthrottled. It also reads `NSEvent.mouseLocation`
instead of `event.mouseLocation` for the local monitor (stale under load).

**Fix:** coalesce with a 16–33 ms `DispatchSourceTimer` (store latest point,
drain on timer). Short-circuit in `DockController.onMove` when no panel has
`autoHide` + edge-hover enabled. Use `event.mouseLocation` for the local monitor.

### M8. Empty dock still renders an empty glass strip
**`Jetty/Screens/DockLayout.swift:41-43` + `DockController.swift`** · UX

When the user removes every item, `contentSize(tiles: [])` falls back to the
1-tile placeholder size — a real glass strip with nothing inside, still
revealing/hiding on edge hover. Feels unfinished. (Root cause: **L35**.)

**Fix:** skip panel creation when `model.tiles.isEmpty`, or hold it permanently
hidden with a one-time "+ drop apps here" hint.

### M9. `DockLayout.alignAlong` offset is silently a no-op at alignment extremes
**`Jetty/Screens/DockLayout.swift:106-119`** · UX

For `.trailing`, `origin = hi − length; origin += offset; clamp`. Positive
offset (spec: "toward trailing") pushes past `hi − length` and is clamped away —
the Settings slider appears broken when trailing-aligned. Same for negative
offset on `.leading`.

**Fix:** document the clamp behavior in the Settings UI, or redefine the
semantics so offset is always meaningful (e.g. inward from the alignment edge).

### M12. Currency formatting uses unit-converter precision (4 dp) and ISO codes
**`Jetty/Menu/JettyMenuModel.swift:70`** · VISUAL/UX

`"\(UnitConverter.format(value)) \(parsed.to)"` → `100 USD to EUR` shows
`91.2345 EUR`. Four decimals is wrong for money (should be 2, or 0 for JPY/KRW),
and the ISO code shows instead of `€`.

**Fix:** `NumberFormatter(currencyStyle: .currency)` with `currencyCode = parsed.to`.

### M13. Recents store does a `stat()` syscall per entry per keystroke
**`Jetty/Menu/RecentAppsStore.swift:36-42` + `JettyMenuModel.swift`** · PERFORMANCE

`recentsProvider?()` → `recentItems()` → UserDefaults decode →
`compactMap { FileManager.default.fileExists(atPath:) }` — up to 8 `stat()` calls
on the main thread on every character typed. Noticeable on a network homedir.

**Fix:** cache `recentItems()` in the model, invalidated only on `record(...)`.
Have `RecentAppsStore` publish via Combine.

### M14. Calculator/conversion/currency: no `⌘C` to copy the answer
**`Jetty/Menu/JettyMenuView.swift`** · UX

Click-to-copy and `Return`-to-copy work now, but `⌘C` doesn't (would copy nothing
or the selected row's text). `⌘⇧C` would be the natural binding.

### M16. Power row is mouse-only; 9 pt labels; no typed access
**`Jetty/Menu/JettyMenuView.swift:227-244` + `JettyMenuController.swift` key monitor** · UX/A11Y

The 6 power buttons are SwiftUI `Button`s with no `@FocusState` — unreachable by
keyboard. Typing "sleep" doesn't surface a Sleep command-row. `Text(title).font(.system(size: 9))`
is below the system "small" and doesn't participate in Dynamic Type. The menu key
monitor still handles only ↑/↓/Return/Esc — no `⌘1–9` result jumps, no
`⌘Return` (the enhancement half of the former M15).

**Fix:** add `MenuCommand` cases for each power command (so they're typed), give
the row a `@FocusState`/Tab stop, use `.caption2`, and add `⌘1–9` / `⌘Return` to
the key monitor.

### M19. `appToRestoreOnClose` can be nil (frontmost quit) → Jetty left frontmost
**`Jetty/Menu/JettyMenuController.swift:66-75`** · BUG

If the captured frontmost app quits while the menu is open, `close()` finds
`appToRestoreOnClose == nil` and does nothing — leaving Jetty (an `LSUIElement`
accessory) as "frontmost". Users see no menu bar until they click another app.
(The *opposite* case — stealing focus back from an app the user clicked — was
fixed; this nil case remains.)

**Fix:** fall back to activating Finder when `restore` is nil and Jetty is active.

### M20. Accessibility: widgets/tiles expose only a static label
**`Jetty/Dock/DockTileView.swift:41-44` + all of `Widgets/`** · A11Y

`.accessibilityValue` is hard-coded to `"Running"`/`""`. For info widgets — clock
time, battery %, CPU/RAM, temp, track, pomodoro remaining — the visible info is
**not** exposed to VoiceOver at all. A VoiceOver user only hears "Clock". No
`.accessibilityAction(.default)` on tiles.

**Fix:** each widget publishes its display string as `.accessibilityValue` (e.g.
Battery → `"53 percent, charging"`). Add `.accessibilityAction(.default) { onTap() }`
and a hint per kind. `.accessibilityElement(children: .ignore)`.

### M21. Settings accessibility gaps
**`Jetty/Settings/GeneralView.swift`, `AppearanceView.swift`, `AngleDial.swift`, `MenuView.swift`** · A11Y

Sliders expose `.accessibilityValue` as a bare percentage, not "52 pt". `AngleDial`
is drag-only — no stepper, no `accessibilityAdjustableAction` (its
`accessibilityValue` was made crash-safe, but not adjustable). Menu glyph buttons
use `.help()` (tooltip) not `.accessibilityLabel`. `HotkeyRecorder` reads its
current binding to no one.

**Fix:** `.accessibilityValue("\(Int(x)) pt")` on sliders;
`accessibilityAdjustableAction` on the dial (±5°); `.accessibilityLabel` on
glyph buttons and the recorder.

### M22. `panel.level = .popUpMenu` may be too aggressive
**`Jetty/Dock/DockPanelController.swift:90`** · VISUAL/UX

`.popUpMenu` is one of the highest standard levels — higher than `.statusBar`,
equal to actual pop-up menus. A Jetty dock at this level can float *over*
contextual menus, file dialogs, and other apps' popovers. The system Dock uses a
level just above normal windows.

**Fix:** drop to one above normal app windows but below pop-ups, e.g.
`NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 2)`. Verify it still
floats over fullscreen (it should, given `.fullScreenAuxiliary`).

### M23. `screenEntries` recomputes UUIDs on every Settings body re-render
**`Jetty/Settings/DisplaysView.swift:57-64`** · PERFORMANCE

`NSScreen.screens` + `registry.key(for:)` (which calls `CGDisplayCreateUUIDFromDisplayID`)
on every body recompute — including every slider drag. The array identity changes
each call, so SwiftUI's diff treats the `ForEach` as fully invalidated. (The sibling
per-render work in MenuView/WidgetsView was fixed; this one was not.)

**Fix:** cache entries in `@State`, refresh on `didChangeScreenParametersNotification`.

### M24. `ItemsView.row` loads icons via `NSWorkspace`/`NSImage` on every render
**`Jetty/Settings/ItemsView.swift`** · PERFORMANCE

`NSImage(contentsOfFile:)` (sync disk read) and `urlForApplication(withBundleIdentifier:)`
(LaunchServices query) per row per render. 30+ items × every prefs tick = janky.

**Fix:** wrap in a cache keyed by `item.id + customIconPath + bundleIdentifier`.

### M26. Folder stack loads icons for all entries *before* the 128-entry prefix
**`Jetty/Stacks/FolderStack.swift:28-44`** · PERFORMANCE

The `prefix(limit)` cap is applied after mapping every URL through
`NSWorkspace.shared.icon(forFile:)`. A 10 000-file folder does 10 000 icon loads
before trimming to 128.

**Fix:** sort first (using only `name` + `isDirectory` from one
`resourceValues` call), `.prefix(limit)`, then load icons only for the 128 kept.

### M31. Currency API leaks the user's IP to a third party on every menu open
**`Jetty/Menu/CurrencyService.swift:25` + `JettyMenuController.swift`** · PRIVACY

`ensureFresh()` hits `https://api.frankfurter.app/latest?from=USD` (third party)
on every `show()`, no opt-in. The first time the user opens the menu, their IP
goes to frankfurter.app. `AGENTS.md` doesn't flag this.

**Fix:** fetch lazily only when `computeCurrency()` parses a query but rates are
empty. Add an on/off toggle in Settings.

### M33. Pomodoro completion: only a sound, no notification
**`Jetty/Widgets/PomodoroTimer.swift:97-102`** · MISSING

The `mm:ss` → `h:mm:ss` label overflow is fixed. Still missing: if the dock is
hidden, another app is focused, or the system is muted, the user has no idea their
Pomodoro finished — it only plays the Glass sound.

**Fix:** post a `UNUserNotification` ("Pomodoro complete — take a break!").

### M35. AppleScript power commands: no per-command confirmation wording
**`Jetty/Menu/JettyMenuController.swift:112-124`** · UX

`"Are you sure you want to \(command.title.lowercased())?"` produces "are you sure
you want to empty trash?" (missing article/capitalization). `PowerCommandRunner.run`
also has a non-exhaustive switch with `default: break` — adding a non-AppleScript
command silently does nothing.

**Fix:** add a `confirmationPrompt` per `PowerCommand`. Drop the `default` and
make the switch exhaustive (or carry an `action: () -> Void`).

### M36. `uniqueDestination` has an unbounded `while true` and no symlink defense
**`Jetty/Updates/UpdateDownloader.swift:24-39`** · BUG/SECURITY

A malicious local process creating thousands of `Jetty-X.dmg` files can spin this
loop (effective DoS). No `isDirectory`/symlink check — a symlink at the candidate
path makes `fileExists` misreport.

**Fix:** cap at ~10 000 iterations and throw on overflow; treat symlinks
explicitly via `lstat`.

### M38. SystemDock re-assert can thrash `killall Dock`
**`Jetty/SystemDock/SystemDockController.swift:37-101`** · BUG/UX

`reassertIfManaging()` has no debounce; wake + screen-change can fire nearly
simultaneously and issue two `killall Dock` calls within ~1 s, on some machines
making the Dock thrash or flash. If Jetty is force-quit between `isManaging = true`
and `restartDock()` returning, the system is left in the managed state with no
Jetty running. (The single-instance guard added in 2026-07 reduces, but doesn't
remove, the second risk.)

**Fix:** coalesce `killall Dock` calls (1 s `DispatchWorkItem` debounce). Add a
launch-time auto-recovery: if a stale `isManaging=true` is detected and the user
didn't opt in this session, restore. Add a "Force restore System Dock" menu item.

### M39. `BoingBallDecoration` / `TileAccent` static mutable globals aren't thread-safe
**`Jetty/Common/BoingBallDecoration.swift:99-100` + `TileAccent.swift:10`** · ENHANCEMENT

Mutable statics touched from `body` only because today is main-thread. Moving
toward Swift 6, these race if any view ever composes on a background queue.

**Fix:** wrap in a `final class` actor or `@MainActor` singleton.

### F-M4. Power commands / dark-mode toggle run AppleScript synchronously on the main thread
**`Jetty/Menu/PowerCommands.swift:79-85` + `Jetty/Menu/MenuCommand.swift:48-52`** · BUG/PERFORMANCE · needs-device-verify

AppleEvent sends block the calling thread (up to the two-minute AE timeout, or
until the first-use TCC consent is answered), and the menu closes *before* running
— so "Empty Trash" grinding through a large Trash freezes the whole app, dock
panels and all, with no visible cause.

**Fix:** run the script on a dedicated serial queue (NSAppleScript isn't
main-thread-bound, just not concurrency-safe), hop back to main for the error
surface (pairs with H21).

### F-M6 / F-P3. Live sampler: post-sleep rate spike, graph seam, and over-publishing
**`Jetty/Widgets/LiveSystemStats.swift:81-93, 54-69`** · BUG/PERFORMANCE

Three issues in the shared sampler (no fix branch landed for these):

- **Rate spike (F-M6):** `sample()` divides the byte delta by the nominal 2 s
  `interval`, not the actual elapsed time. After sleep (Power Nap keeps transferring)
  or timer coalescing, the first delta covers hours but is divided by 2 s — a
  "50 MB/s" spike. Track real elapsed time; drop the baseline when the gap is large.
- **Graph seam:** `startTimer()` resets `lastNetwork` but not `history`, so a
  restart splices pre-gap samples onto post-gap ones as one continuous 2-minute line.
- **Over-publish (F-P3):** `sample()` assigns `load`/`memory`/`history` (and battery)
  unconditionally each tick → 3–4 `objectWillChange`/2 s; and a battery-only dock
  still runs the CPU/mem/net syscalls nobody displays. Guard the assignments and
  scope the syscalls to the widgets actually shown.

### F-M12. Tile clicks can target a different process than the tile represents
**`Jetty/Apps/RunningAppsModel.swift:63-79`** · BUG

The published snapshot dedups duplicate bundle-ids keeping the **first** instance;
`indexByBundle` keeps the **last**. In exactly the dual-instance scenario the dedup
comment itself calls real, the tile renders instance A's `pid`/`isActive` while
clicks, Show/Hide/Quit, and the active glow operate on instance B — "Quit" can
terminate a different process than the tile shows.

**Fix:** make both sides agree on the representative (first-wins, or prefer the
active instance).

### F-M13. Apps that change activation policy at runtime never appear/disappear
**`Jetty/Apps/RunningAppsModel.swift:34-50`** · BUG

The model listens to six NSWorkspace notifications; none fires when a running app
flips `activationPolicy` (Electron tray-mode toggles, "Show Dock icon" preferences).
The real Dock updates immediately; `NSWorkspace.runningApplications` is
KVO-observable for exactly this.

**Fix:** KVO-observe `runningApplications` (store the observation, invalidate in
`deinit`); pair with an equality gate (F-P4) so it doesn't add redundant rebuilds.

### F-M14 / F-U8. Background update check steals focus; download has no feedback
**`Jetty/Updates/UpdateChecker.swift:91,184-203,227-236`** · UX

`runModal` unconditionally activates Jetty first, and background checks reach it —
with launch-at-login, the user logs in, starts typing, and Jetty yanks activation
to a modal alert (a stray `Return` = Download). The only place in the app that
activates without a user gesture, against the project's never-steal-focus discipline.
Separately, the Download path has **zero** UI: `isDownloading` is published but
observed by nothing, and failure silently opens a browser tab.

**Fix:** for background checks, present without activating (or post a
`UNUserNotification` / defer to the next user interaction). Wire `isDownloading`
into AboutView and replace the silent browser fallback with an explained alert.

### F-P1. Icon cache TTL causes a synchronized main-thread re-resolve storm every 5 min
**`Jetty/Common/IconCache.swift:24-29` + `Jetty/Dock/DockModel.swift:41`** · PERFORMANCE

`LRUImageCacheByKey` treats an entry as dead at a hard absolute TTL, set only at
insert and with no jitter. `DockModel` populates essentially every tile's icon in
one first rebuild, so every ~5 minutes all entries cross the TTL in the same second
and the next rebuild takes the miss path for every tile at once — N synchronous
`NSWorkspace.icon(forFile:)` calls on the main thread, forever, in lockstep.

**Fix:** jitter each entry's effective age, or serve-stale-while-revalidate (return
the stale image immediately and refresh async — also removes the M1 hitch).

### F-P2. Hovering a folder tile does synchronous bookmark I/O on the main thread up to 3× per hover
**`Jetty/Dock/DockController.swift:272-282`** · PERFORMANCE

`handleTileHover` → `hoverPreview(for:)` evaluates `liveURL(for: tile)` for every
folder tile on every hover ENTER, which calls `store.resolvedURL(forItemID:)` →
`BookmarkResolver.resolve` — synchronous security-scoped bookmark resolution (that
can stat the filesystem and write back) on the main thread, mid-pointer-tracking.
`applyPreview()` and `presentFolderStack` resolve it again.

**Fix:** for hover-eligibility, don't resolve bookmarks at all (`tile.url != nil ||
tile.itemID != nil` is enough); resolve the live URL once, after the dwell.

### F-P4. `RunningAppsModel.refresh()` publishes identical snapshots
**`Jetty/Apps/RunningAppsModel.swift:59-80`** · PERFORMANCE

`refresh()` always reassigns `@Published var apps`, and `DockController` rebuilds
on every emission. But `RunningAppInfo` carries no hidden flag, so `didHide`/
`didUnhide` notifications can only ever produce an array equal to the previous one
— each still costs a full `rebuildModel()` + `relayoutPanels()`. `RunningAppInfo`
is already `Equatable`.

**Fix:** end `refresh()` with `if new != apps { apps = new }`.

### F-P7. `BoingBallDecoration`'s single-slot bitmap cache thrashes on mixed-DPI multi-monitor
**`Jetty/Common/BoingBallDecoration.swift:99-125`** · PERFORMANCE

`cachedSmooth` is a single `(pixelDiameter, image)` tuple keyed by
`diameter * displayScale`. A Retina laptop (scale 2) plus a 1× external display
produce two different pixelDiameters, so every shared render trigger makes the two
panels alternately evict each other's rasterized sphere — a full CPU rasterization
loop the cache contract promises never happens on the hot path. (Only when the
Amiga decoration is enabled.)

**Fix:** replace the single-slot tuple with a small dictionary keyed by
pixelDiameter (2–3 entries in practice).

---

## Low / polish

- **L1 — `CarbonHotkey`** (`Hotkeys/CarbonHotkey.swift:57-64`): one
  `InstallEventHandler` per instance; `Unmanaged.passUnretained(self)` as
  `userData` is only safe if `deinit` runs on the main thread. Use a single
  shared app-wide handler that just `RegisterEventHotKey`s per instance.
- **L2 — `SemanticVersion`** (`Updates/SemanticVersion.swift:34`): main
  components accept leading zeros (`01.02.03`) but pre-release doesn't —
  inconsistent with SemVer §2.3. Reject or document.
- **L4 — `UpdateChecker.start()`**: no jitter/back-off; a relaunch wave can hit
  GitHub's 60/h/IP unauthenticated limit. Add `X-RateLimit-Remaining` awareness +
  a randomized initial delay.
- **L5 — `localizedCaseInsensitiveCompare` on every keystroke**
  (`AppSearch.swift`, `AppIndex.swift`): ICU collation on every char. Pre-sort once
  in `AppIndex`; cache the empty-query result.
- **L7 — Recents always shown, no clear/remove** (`JettyMenuModel.swift`): no `×`,
  no "Clear recents", no section header distinguishing recents from the
  alphabetical list. Incognito mode missing.
- **L8 — Web search is Google-only** (`JettyMenuController.swift`): no preference for
  DuckDuckGo/Brave/Kagi/system engine.
- **L9 — `NSColor.hexString` discards alpha** (`ColorHex.swift:32-39`): always
  `#RRGGBB`; `init?(hex:)` parses 8 digits, so a round-trip loses alpha. Emit
  `#RRGGBBAA` when `alphaComponent < 1`.
- **L10 — `ColorHex.init?(hex:)` rejects CSS shorthand** (`ColorHex.swift:8-30`):
  no `#RGB`/`#RGBA`. Hand-edited themes commonly use it.
- **L11 — `jettyColorBinding` silently swallows bad hex + drops alpha**
  (`SettingsView.swift:37-40`): picker goes transparent while stored hex stays
  bad. Configure `ColorPicker` with `supportsOpacity: false` to match storage.
- **L12 — Poof doc comment lies** (`Common/Poof.swift:4-11`): promises "plus the
  system sound" but only shows `NSAnimationEffect.poof`. Add a shipped sound or
  fix the doc.
- **L13 — `LRUImageCache` and `LRUImageCacheByKey` are 90% duplicated**
  (`Common/`): collapse into a generic `LRUCache<Key: Hashable>`; the by-key
  variant is missing `removeAll()`.
- **L14 — `GlassBackground` fallback treats all three glass variants identically**
  (`Common/GlassBackground.swift:56-66`): on macOS 13–15/Reduce Transparency,
  `.liquidGlass`/`.glassClear`/`.glassTinted` all become `.hudWindow`. (The Settings
  pane now *documents* that tint/opacity don't apply to Liquid Glass/Clear, but the
  fallback still renders the three variants the same.)
- **L15 — `VisualEffectBlur` forces `.state = .active`**
  (`Common/VisualEffectView.swift:13,19`): when the panel loses key the blur
  still renders active — slight mismatch with system panels.
- **L17 — World-clock zone label gives region, not city** (`WorldClockWidgetView.swift`):
  `US/Eastern` → `Eastern`; no day/night glyph. (Also: `WorldClockWidgetView.timeZone`
  recomputes `TimeZone(identifier:)` on every render — the residual perf nit from
  H14; cache it, recompute only when the preference changes.)
- **L18 — Weather `(0,0)` sentinel + no city name shown**
  (`WeatherWidgetView.swift`): anyone near the Gulf of Guinea can't configure it;
  the tile never shows *which* location. Reverse-geocode the name.
- **L19 — Weather: only current temp, no rich data** (`WeatherService.swift`):
  Open-Meteo returns `apparent_temperature`, humidity, wind, daily hi/lo for the
  same no-key call — ignored. Surface in a tooltip + accessibility value.
- **L20 — System monitor: network is down+up combined**
  (`SystemMonitorWidgetView.swift`): data is already separate; draw two lines.
- **L21 — `normalizedLoad()` is load average, not CPU %** (`SystemStats.swift`):
  takes 30–60 s to converge, can exceed 100 %. Compute true CPU % from
  `host_processor_info` (HOST_CPU_LOAD_INFO) like `top`.
- **L22 — `dlopen` handle never closed; `dlsym` re-resolved per call**
  (`MediaRemoteBridge.m`): `dispatch_once` both the handle and fn pointer. (See H7.)
- **L23 — `WindowPeekView` nests Buttons inside Buttons**
  (`Windows/WindowPeek.swift`): SwiftUI's nested-button hit-testing is unreliable —
  sometimes both fire. Use overlaid tap gestures.
- **L24 — Custom icon path won't follow moves** (`Settings/ItemsView.swift`):
  stores a bare path; if the user moves the source file, the icon vanishes. Copy
  into `Application Support/Jetty/icons/<id>.png` or bookmark it.
- **L25 — No "Reset to defaults" anywhere in Settings** (`Settings/*View.swift`):
  wild experimentation is one-way. Add per-pane reset buttons; `Preferences.Default`
  already centralizes values.
- **L26 — No user-saved presets** (`Settings/AppearanceView.swift`):
  built-ins can be Applied and Exported/Imported, but there's no in-app "My
  preset" for one-click re-apply.
- **L27 — No preset/widget previews in Settings**: configure blind; render a
  small faux dock (3 tiles) per preset, a live preview per widget.
- **L28 — `ItemsView.row` displays wrong state when display disabled**
  (`Settings/DisplaysView.swift`): toggling "Disable dock" hides the controls but
  retains the override; re-enabling surprises the user. Add a "Reset to global
  default" button.
- **L29 — `FolderStackView.header` back button too small**
  (`Stacks/FolderStack.swift`): ~12 pt glyph, below the ~20 pt HIT min. Wrap in
  `.frame(24×24).contentShape(Rectangle())`.
- **L30 — `FolderStackController` Escape requires Jetty frontmost**
  (`Stacks/FolderStackController.swift`): the popover is `.nonactivatingPanel`, so
  the previously-focused app keeps key — Esc dismisses that app's modal, not the
  popover. Click-outside still works; document.
- **L31 — `runningApplication(bundleIdentifier:)` fallback defeats `indexByBundle`**
  (`RunningAppsModel.swift`): the full-scan fallback re-introduces exactly what the
  index avoids. Drop it. (See also F-M12.)
- **L32 — `BookmarkResolver` uses `[]` options** (`Store/BookmarkResolver.swift`):
  fine non-sandboxed, but a future App-Store variant will silently break without
  `startAccessingSecurityScopedResource` at call sites. Add TODOs.
- **L33 — `seedDefaultItems` is English-only** (`DockController.swift`):
  localize the display names; detect a default browser when Safari is absent.
- **L34 — `DockContextAction.id = UUID()`** (`Dock/DockContextAction.swift`):
  context menu rebuilt per right-click mints new ids → no animation continuity.
  Use `id: \.title` (titles are unique).
- **L35 — `DockLayout.contentSize(tiles: [])` returns the 1-tile placeholder**
  (`Screens/DockLayout.swift:41-43`): root cause of M8. Return `.zero` and let
  the caller decide on a placeholder.
- **L37 — `dockDefaults?.synchronize()` is deprecated/best-effort**
  (`SystemDockController.swift`): the relaunched Dock may briefly show the user's
  original delay. Document.
- **L38 — `AppLauncher.openApplication` always launches, never switches**
  (`JettyMenuController.swift`): if the app is already running, this may open a new
  window or do nothing useful. Switch-if-running like dock tiles do.
- **L39 — No "drag result row to dock to pin"** (`JettyMenuView.swift`): menu rows
  aren't draggable. Common Alfred→dock interaction.
- **L40 — No settings ⌘F search**: 8 tabs, ~60 controls — discoverability is
  rough. macOS users expect it.
- **L41 — `UnitConverter` missing common families** (`UnitConverter.swift`):
  no time/duration, area, pressure, energy, angle, fuel, data rate, bits/bytes
  distinction.
- **L42 — `hexString`/`init?(hex:)` reject bare-word colors** (`red`): CSS
  keywords are common in hand-edited themes.

### From the Fable review (still open)

- **F-L5 — App search is word-order sensitive** (`Menu/AppSearch.swift:49-89`):
  "studio visual" finds nothing for Visual Studio Code — the query matches as a
  single ordered subsequence. (Diacritic/width folding is done.) Tokenize on
  whitespace and AND the tokens for multi-word queries.
- **F-L10 — NowPlaying safety net can let a stale callback overwrite a fresher snapshot**
  (`Widgets/NowPlayingService.swift:19-35`): abandoned fetches aren't invalidated;
  use a generation token instead of a Bool `inFlight`.
- **F-L11 — `TrashMonitor` never re-arms** (`Apps/TrashMonitor.swift:13-30`): after
  the watched `~/.Trash` vnode is deleted/recreated it keeps watching the dead vnode;
  a failed `open()` silently disables the tile with no log/retry. Re-open the path on
  `.delete`/`.rename`.
- **F-L12 — Vertical docks give a separator a full icon-height slot for a 1-pt line**
  (`Screens/DockLayout.swift:57-67`): 4× the 12 pt gap it gets horizontally. Return a
  12 pt along-extent on vertical edges (keep `DockLayout` and `DockTileView` in sync).
- **F-L13 — `DockLayout.hiddenFrame` / `edgeReveal` are dead code**
  (`Screens/DockLayout.swift:14,126-136`): hiding is done by `hiddenTransform()`,
  which ignores them; only tests exercise them. Delete, or re-route `hiddenTransform`
  through the pure function so it stays the source of truth.
- **F-L14 — `AppLauncher.open(_ item:)` / `resolvedURL(_:)` are dead code**
  (`Apps/AppLauncher.swift:9-26,71-73`): unused (this is the old M37 path), and they
  silently disagree with the live path (no bookmark write-back). Delete them.
- **F-L15 — Update checker reports "You're up to date" when a version fails to parse**
  (`Updates/UpdateChecker.swift:125,135-138`): a false "up to date" hides real updates;
  a user-initiated `checkNow()` during an in-flight background check silently no-ops.
  Present a distinct "couldn't compare versions" message; don't swallow the manual check.
- **F-L16 — Launch-at-login failure is swallowed silently**
  (`Model/Preferences.swift:359-370`): with the login item disabled in System Settings
  or `.requiresApproval`, the toggle just snaps back. Call
  `SMAppService.openSystemSettingsLoginItems()` and/or explain it.
- **F-V1 — Hover name labels are clipped** (`Dock/DockTileView.swift:199-206`): the
  label uses a fixed `.offset(y: -baseSize * 0.75)` ("up" regardless of edge) and the
  panel clips (`masksToBounds`), so "Show name on hover" is invisible with magnification
  off and always clipped on top-edge docks. Make the offset edge-aware and reserve label
  headroom in `contentSize()`. *(needs-device-verify)*
- **F-V2 — Wide widget tiles overflow the glass strip on vertical docks**
  (`Dock/DockView.swift:33,131-153`): the strip is a fixed `iconSize + 2·padding` thick
  while the panel is sized from the widest tile, so a clock/now-playing tile floats past
  the glass (and is cropped in overflow-scroll). Compute the strip thickness from the
  widest tile.
- **F-V3 — Drag-out tile vanishes under the panel mask before the removal threshold**
  (`Dock/DockView.swift:316-322`): ~26–40 pt of visible travel vs the ~83 pt required
  (none with magnification off) — the user drags an invisible tile with no cue. Show a
  floating ghost/removal hint, or lower the threshold to the visible headroom.
- **F-V4 — Active-glow dots + peek/stack anchors misplaced in overflow-scroll mode**
  (`Dock/DockView.swift:157-177`): both re-derive layout math that assumes the centered,
  non-scrolled layout and don't track the scroll offset. Suppress glows in overflow, or
  read real tile frames via anchor preferences.
- **F-V5 — End tiles clip when the dock nearly fills the screen** (`Dock/DockPanelController.swift:320-333`):
  in the band where the panel is clamped to `visibleFrame` but not yet overflowing, the
  magnification headroom is eaten but magnification stays on. Disable magnification in
  that band (treat clamped-but-not-overflowing like overflow).
- **F-V6 — `GlassBackground` reads Reduce Transparency non-reactively**
  (`Common/GlassBackground.swift:69-71`): nothing re-renders when the accessibility
  setting toggles. Use `@Environment(\.accessibilityReduceTransparency)`.
- **F-V7 — Angle row has no numeric readout** (`Settings/AppearanceView.swift:21-25`):
  the doc comments were corrected to say the gradient angle increases counterclockwise,
  but unlike every slider the Angle row shows no degree value. Add `Text("\(Int(angle))°")`.
- **F-U2 — No first-run onboarding**: launch → the menu-bar glyph appears and the
  system Dock vanishes with no welcome. A one-time panel ("here's how to reveal, here's
  Restore, here's Settings") removes the scariest moment. The `!store.loadedFromDisk`
  seed path is the natural hook. *(product decision)*
- **F-U6 — Minimized windows are invisible in Jetty**: the system Dock shows minimized
  windows as thumbnails; Jetty's window-peek lists windows but marks none minimized and
  offers no unminimize. With the AX machinery already shipped (opt-in), a ⊖ badge in
  WindowPeek rows is cheap. *(product gap)*
- **F-U9 — Settings slider ranges disagree with model clamps**
  (`Settings/GeneralView.swift` vs `Preferences`/`DockAnchor`): reveal delay 0–600 vs
  0–1000; hide 0–1500 vs 0–2000; inset 0–80 vs 0–400. A model-legal value renders with a
  pinned thumb and a contradicting label, and the first drag silently rewrites it. Pick
  one source of truth.
- **F-R6 — `UpdateDownloader` tests aren't hermetic** (`JettyTests/GitHubReleaseTests.swift:45-59`):
  they run `uniqueDestination` against the real `/tmp`; a leftover `Jetty.dmg` makes them
  flaky. Use a per-test temp dir (as `MenuGlyphAndStoreTests` does).
- **F-R9 — `DockStore`'s `.bak` rotation has no unit test** (`JettyTests/MenuGlyphAndStoreTests.swift:27-43`
  only tests the `fileDecodes` helper): add recover-from-corrupt-primary,
  don't-overwrite-good-bak, and round-trip tests — the store is fully injectable.
- **F-R10 — build/release scripts exec an unpinned external engine** (`scripts/build.sh`,
  `release.sh`): `lkm-build`/`lkm-release` are resolved from PATH (or an env override) with
  no version/integrity check, so the release *tagging* step depends on whatever binary is
  installed. Assert a minimum engine version / pin the `release-tool` commit.

---

## Delightful feature ideas

A menu of novel/cool/quirky improvements, roughly ordered by "wow per effort."

### Squish / magnify-shift (the real-Dock feel)
H8's fix is also the headline feature: integral-of-the-magnification-curve
neighbor shifting. Single biggest perceived-quality jump.

### Bounce-on-launch animation
The classic Dock behavior. You have `RunningAppInfo.isActive` and a spring on
the tile already; an `isLaunching` state with a vertical `.spring` repeat would
be immediately familiar and delightful.

### Spring-loaded folders
Dragging a file over a folder tile, after a short dwell, opens the stack
mid-drag (Finder-style) so the user can navigate into a sub-folder and drop
there. `NSDraggingInfo` has `draggingSpringLoading` hooks.

### Badge / unread-count overlays
Per-tile accent color exists (`TileAccent`). Let the user override it per pinned
item, or expose a small numeric badge fed by a user script (the DragThing/
AlarmDock unix-philosophy pattern).

### Per-display personalities
Each display gets a subtle independent accent/preset: work monitor = sober
command strip, laptop = playful glass + widgets. (Needs per-display appearance
overrides + settings UI.)

### Edge reveal "heat map"
A brief, optional glow in the reveal band after failed edge attempts — teaches
users where the dock lives without leaving a permanent sliver.

### Dock "breathing" on wake
After wake/display reconnect, pulse the dock once to communicate it reclaimed the
system-Dock state and restored placement.

### Stuck-dock self-heal watchdog
If no `mouseMoved` has fired in N seconds, no panel is revealed, and no panel's
transform matches expectation → force `recomputeFrames` + `applyRevealState`.
Catches rare suspend/resume/reconfigure half-states.

### Reveal trigger = `.hotkeyOnly`
An explicit "hotkey only, no edge hover at all" mode that disables the global
mouse monitor entirely (saves M7's overhead) — useful on laptops where edge work
shouldn't trigger anything.

### Drag-out-to-promise
Drag-out currently removes (with poof). Alternative: drag to a screen edge tears
the tile off into a transient floating "pulled-out" widget. Distinctive.

### Per-tile "Options → Assign to Space N"
Right-click submenu to move a tile to a specific Space — a genuine Dock
power-use feature missing from the system Dock on Tahoe.

### Live now-playing artwork
`MRMediaRemoteGetNowPlayingArtwork` (same private framework you already use) →
album art on the now-playing tile.

### Pomodoro heat-square
"Today: 4 sessions" with a tiny GitHub-contributions-style grid. Generalize to
named timers / a stopwatch.

### Sunrise/sunset, moon phase, AQI, UV tiles
All free (NOAA sunrise equation is pure computation; Open-Meteo's air-quality
API uses the same no-key model as weather). Moon phase is pure computation, no
network — beautiful with a tiny rendered moon.

### Next-calendar-event tile
"in 12 min: 1:1 with Sam" with a one-click Join (opens the Zoom/Meet URL).
EventKit needs Calendar permission (opt-in).

### Stock / crypto sparkline, GitHub-stars tile, uptime probe
Public APIs, no key. Nice for power users.

### Disk space, CPU/GPU temp, Time Machine status, Focus/DND toggle tile
Natural companions to the existing system-monitor tile. Temperature would be SMC
(private — keep isolated/fail-closed per AGENTS.md).

### Multi-city world-clock carousel + day/night shading
Cycle zones on hover; a thin horizontal bar showing where it's day vs night
around the globe.

### Window switching in the Jetty Menu
Top-3 reasons people install launchers. Window switching is half-built
(`AppWindows.swift` exists) — expose it.

### Open-URL detection in the menu
If the query parses as a URL/host (`apple.com`, `https://…`), offer to open it
directly in the browser instead of routing through Google.

### "Open with…" / process manager / Show-in-Finder
Right-click on an app row: Get Info, Reveal, kill running instance.

### Verified-publisher badge on the update alert
Once C1 signatures land, change the alert to "verified from \<Team ID\>" — a
small trust signal that distinguishes a serious dock replacement.

### Per-app signature-preflight on tile launch
Since Jetty already holds Automation + is non-sandboxed, optionally
`SecStaticCodeCheckValidity` a pinned app before launch and warn if its
signature changed ("Safari.app has been modified since you pinned it — open
anyway?"). A delightful security feature no other dock offers.

### Theme camera / eyedropper
Sample a color from the screen to set `tintHex` directly.

### Hotkey chords
`⌃⌘K then ⌃⌘D` style sequences.

### Settings: verified-updates pane, search (⌘F), preset previews, live widget previews
Trust + discoverability. A "last installed version/date", "channel" toggle, and
"verify update signatures" checkbox once C1 lands.

### New from the Fable review

- **`jetty://` URL scheme + Shortcuts hooks.** `jetty://toggle`,
  `jetty://reveal?display=uuid`, `jetty://menu`, `jetty://preset/Vapor`,
  `jetty://pomodoro/start?minutes=50`. One `NSAppleEventManager` handler in
  `AppDelegate` fans out to `DockController`/`Preferences.apply` — instantly
  scriptable from Shortcuts, Raycast, shell (`open jetty://…`), BetterTouchTool.
- **Scroll-wheel gestures on tiles.** Scroll over an app tile → cycle that app's
  windows (the `AppWindows` raise machinery already exists); over the pomodoro →
  nudge minutes; over the world clock → cycle favorite zones. `DockTileView` just
  needs a scroll monitor.
- **Option-drag a tile = duplicate as a floating mini-launcher**, and **⌘-hover a
  tile to peek its real path** in the label (power users constantly want "where is
  this app really?").
- **Day/night auto-theming.** The weather tile already knows coordinates; a NOAA
  sunrise calc is pure math. At sunset, cross-fade to a chosen preset
  (`Preferences.apply` exists; presets are shareable).
- **Preset cards.** On export, also render the current dock into a PNG "theme card"
  (a 3-tile faux dock) so shared `.json` themes come with a preview — makes a
  community theme gallery viable.
- **Per-tile launch hotkeys.** `⌥1…⌥9` activate the Nth dock tile — `CarbonHotkey`
  infrastructure is already there and the tile order is user-curated. (uBar charges
  for this; the system Dock never had it.)
- **Trash X-ray.** `TrashMonitor` already watches the Trash; the tooltip / VoiceOver
  value could say "14 items · 3.2 GB" from one `contentsOfDirectory` +
  `totalFileAllocatedSize`, cached on the monitor's events. Pairs with IDEA-5.
- **Pomodoro in the menu-bar glyph.** While the dock is hidden (95% of the time), the
  status item is Jetty's only visible surface: swap `statusBarImage()` for a tiny
  progress ring while a session runs.
- **Haptic detents on magnification.** `NSHapticFeedbackManager.defaultPerformer
  .perform(.alignment)` as the hover crosses tile centers — Force-Touch trackpads turn
  the dock into something you can *feel*. Three lines, gated by a preference.
- **"Focus dock" per Space/app.** When permission-free window peek knows the frontmost
  app, a rule like "when Xcode is frontmost, show only the Dev folder's tiles" (per-app
  tile filters) is a genuinely new dock capability — `DockModel`'s pure merge makes the
  filter a one-liner.
- **Battery time-to-full/empty in the tooltip** — `IOPSGetTimeRemainingEstimate` is
  public and free; the battery tile's `.help` currently says just "Battery".
- **Konami-code boing.** Typing "boing" in the Jetty Menu bounces the Amiga ball across
  the dock once (the `BoingBallDecoration` renderer + a keyframe animation).

---

## What's done well

To balance the punch list — the architecture is sound and most of this is
polish, not rework:

- **The core-dock permission-free promise is real.** No Accessibility, no
  `CGEventTap`, no global *key* monitor, no private APIs in the core path.
  `CarbonHotkey`, `NSWorkspace`, `RegisterEventHotKey`, mouse-only global
  monitor. Excellent discipline — and exactly the load-bearing design decision
  `AGENTS.md` calls out.
- **The reveal/hide rework** (window parked, content-layer transform only) is the
  right architecture — pure GPU compositing, no SwiftUI re-layout mid-slide, with a
  mid-animation convergence guard.
- **Pure/UI separation is clean.** `DockLayout`, `MagnificationCurve`,
  `ClockFormatter`, `AppSearch`, `DockModel.makeSlots`/`makeTiles`,
  `PowerCommand` mapping, `ExpressionEvaluator`, `UnitConverter`,
  `CurrencyService.parse`, `MenuCommand.match`, `FolderStack`,
  `SystemStats`/`WeatherService` formatting, `HotkeyBinding`,
  `NowPlayingService.parse`, `SemanticVersion` are all unit-tested and
  side-effect-free.
- **`DockStore`'s `.bak` rotation guarded by `fileDecodes`** (a corrupt primary
  can't overwrite the last good backup) is exactly the right defensive pattern.
- **Lossy Codable decoding** (`Failable<T>` in `DockDocument.swift`) means one
  bad item/anchor no longer loses the whole dock.
- **The MediaRemote legacy `dlopen` path is exemplary** — `dlopen` → `dlsym` →
  nil-return fail-closed; and the controller path now matches it (fails closed).
- **`SystemDockController` captures prior autohide/delay/time-modifier** and
  restores them faithfully rather than clobbering user prefs.
- **`RunningAppsModel`'s bundle-id dedup** with the clear comment about why
  (magnification center-map desync) shows real understanding of downstream
  consequences — the comment is what let a later review catch that the same
  invariant wasn't fully enforced for *pinned* duplicates (now fixed).
- **CI is now hardened**: both workflows declare minimal `permissions:`,
  cancellation is PR-only, `timeout-minutes` bounds every job, the release path
  runs the test suite and marks prerelease tags correctly, and the Xcode version is
  pinned. (Actions are still on floating tags — see C3.)
- **Combine subscriptions consistently use `[weak self]`**; `LiveSystemStats`
  centralizes what would otherwise be N independent timer storms; the 32-bit
  counter wrap is *caught* (clamped to 0) rather than producing garbage.

---

## Roadmap & open product items

Distilled from `PLAN.md` — the product/roadmap items a code review doesn't otherwise
capture. (Feature-level *ideas* live under
[Delightful feature ideas](#delightful-feature-ideas).)

**Later / opt-in features not yet built**

- **Badge / unread-count mirroring** (`PLAN.md` Phase 11) — best-effort via the
  undocumented AX `AXStatusLabel` / `lsappinfo`; Accessibility-gated, private-API-aware.
- **Taskbar / multi-row mode** (`PLAN.md` Phase 12). Horizontal overflow-scroll shipped
  as the interim answer to "too many tiles."
- **Spaces / Stage Manager tuning** — overlay there is best-effort; the default is hide
  + hover/hotkey reveal.

Window peeking (Phase 9) and live ScreenCaptureKit previews (Phase 10) have already
**shipped** as opt-in features.

**Release engineering (maintainer step)**

- On-device GUI verification each release (windowing, multi-monitor, reveal/auto-hide,
  Dock-hide, Liquid Glass, drag-and-drop, power commands — none unit-testable).
- Developer ID signing + notarization — CI publishes an unsigned ad-hoc build. Overlaps
  the **C1/C2** findings above.

**Permanent non-goals (platform constraints)**

- No true replacement / disabling of the system Dock (SIP-protected, no public API).
- No screen-space reservation / window-nudging in the core (keeps the dock
  permission-free — the load-bearing design decision).
- No App Store build (the sandbox precludes the Accessibility the window features need).

**Standing risks**

- Auto-hide fragility on Tahoe (26.0–26.1) — mitigated by re-asserting the
  `com.apple.dock` defaults on launch / wake / screen-change plus one-click Restore.
- Private-API drift — the MediaRemote bridge (and any future `_AXUIElementGetWindow` /
  `AXStatusLabel`) stays isolated, `dlopen`/weak-imported, opt-in, fail-closed; re-test
  each macOS beta. See **H7** for the current MediaRemote perf issue.

---

## Earlier review history

**GPT-is-awesome review** (2026-06-28, previously in `GPT-is-awesome.md`, folded here):
fully addressed. BUG-1 … BUG-13 (implement-now bugs) — all fixed. ISSUE-1 … ISSUE-9
(design-level) — all fixed: activate bundle-less apps by PID (1); magnified end-tile
clipping (2); now-playing opt-in / isolated / fail-closed (3); off-main-thread folder
stacks (4); one shared throttled sampler `LiveSystemStats` (5); app-index refresh on
menu open + one level deeper (6); stale bookmarks written back to `DockStore` (7);
tolerant/lossy document decoding (8); `.bak` protected from a corrupt primary (9). Its
delight ideas are captured above. Still open from it: **stack spatial memory** (IDEA-4
— folder stacks bias focus to the last-hovered item) and part of **Trash mood** (IDEA-5
— empty/full is live via `TrashMonitor`; remaining: a brief "hot" state after a drop
and a poof on empty).

**Fable review** (2026-07-02, previously in `fable-is-awesome.md`, folded here): its
implemented findings are recorded in
[Implemented and removed (2026-07-02)](#implemented-and-removed-2026-07-02); its still-open
findings carry `F-*` ids throughout the lists above; its corrections are applied in
place (L3 closed as invalid; M37 closed as moot with the dead-code cleanup tracked as
F-L14; the H7/M4 `NowPlayingWidgetView` path corrected to `Jetty/Widgets/`; the
`AGENTS.md` activation-policy note fixed there and reflected in "What's done well").

---

*Living document. Backlog line numbers are current as of `main @ fd579a8`
(2026-07-02); a few may drift as files evolve — the `file:line` citations should
remain easy to relocate.*
