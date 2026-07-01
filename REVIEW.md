# Jetty — Code Review

A thorough review of `main` (v1.0.1) covering bugs, security, performance,
visual/layout, UX, missing features, and delight-level ideas. Findings are
prioritized by severity with concrete fixes and `file:line` references.

The codebase is genuinely high quality — the pure/UI separation is clean, the
"no permission for the core dock" promise is honored, lossy Codable decoding is
defensive, and the `.bak`-guarded store is the right pattern. Most findings here
are polish, robustness, and feature-completeness rather than structural problems.
The exceptions are **§1 (update verification)** and **§2 (MediaRemote crash
risk)**, which I'd fix before anything else.

---

## Table of contents

- [Critical](#critical)
- [High](#high)
- [Medium](#medium)
- [Low / polish](#low--polish)
- [Delightful feature ideas](#delightful-feature-ideas)
- [What's done well](#whats-done-well)

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
**`.github/workflows/release.yml:37-89`** · SECURITY

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

### C3. CI uses a third-party action pinned to a floating tag
**`.github/workflows/release.yml:75`** · SECURITY

`softprops/action-gh-release@v2` (and `actions/checkout@v4`,
`maxim-lobanov/setup-xcode@v1`) are moving tags. If any of those repos is
compromised (high-value targets), an attacker ships a new `v2.x` that exfiltrates
`GITHUB_TOKEN` (`contents: write`) and silently swaps the `.dmg` on every
release. Combined with C1+C2, that's a complete silent-compromise chain.

**Fix:** pin every third-party action to a SHA digest
(`softprops/action-gh-release@<full-sha> # v2.x.y`).

### C4. MediaRemote "controller" path crashes instead of failing closed
**`Jetty/MediaRemote/MediaRemoteBridge.m:83-125` + `JettyBuildInfoFromResponse` 15-57** · BUG/SECURITY

The header and `AGENTS.md` both promise the bridge **fails closed** (returns nil
→ plain glyph). The legacy `dlopen` path honors this. The 15.4+ controller path
**does not**. It calls `performSelector(NSSelectorFromString(@"userSelectedDestination"))`,
`NSSelectorFromString(@"initWithDestination:")`, `setValue:forKey:@"singleShot"`,
`@"requestPlaybackState"`, `@"requestPlaybackQueue"`, `beginLoadingUpdates`,
`endLoadingUpdates`, `valueForKey:@"response"`, and (in
`JettyBuildInfoFromResponse`) `valueForKey:@"playbackRate" / @"playbackState" /
@"playbackQueue" / @"contentItems" / @"location" / @"metadata"` — **none of it
wrapped in `@try/@catch`**.

macOS point releases (especially across Tahoe → 26.x → 27) regularly rename
private-framework selectors. When one shifts, the opt-in now-playing tile will
**kill the whole menu-bar agent** the first time it polls — the opposite of
fail-closed.

**Fix:** wrap the entire controller path body and `JettyBuildInfoFromResponse`
in `@try { … } @catch (NSException *ex) { completion(nil); }`. Add
`-respondsToSelector:` guards before each `performSelector:`. Better:
introspect the class once at first use with `class_copyMethodList` and skip the
controller path entirely if the expected names are absent.

---

## High

### H1. `hosting.sizingOptions` is macOS-14+ but the deployment target is 13.0
**`Jetty/Settings/SettingsWindowController.swift:39`** · BUG

`NSHostingController.sizingOptions` was added in macOS 14.0, but
`MACOSX_DEPLOYMENT_TARGET = 13.0` and `AGENTS.md` claims a macOS-13 min target.
This will crash on macOS 13 at runtime (or fails to compile against the 13 SDK).

**Fix:** wrap in `if #available(macOS 14.0, *) { hosting.sizingOptions = [.minSize] }`.

### H2. Pressing Return on a calculation silently leaks the query to Google
**`Jetty/Menu/JettyMenuModel.swift:108-116`** · BUG/PRIVACY

`activateSelection()` priority is `command → results[selectedIndex] → webSearch`.
The calculator banner is never an activation target for Return. So typing `2+2`,
seeing `= 4`, and pressing Return (the universal "use this answer" gesture in
Spotlight/Alfred/Raycast) falls through to `onWebSearch("2+2")` and opens
`https://www.google.com/search?q=2+2`. The user wanted to copy `4` to the
clipboard; they got a surprise browser trip that also leaks the query. Same
applies to unit conversion (`10 km in miles`) and currency (`100 usd to eur`).

**Fix:** make the calculation/conversion/currency banner the Return target when
present and no app/command is selected:
```swift
if let calculation { onCopyCalculation?(calculation); return }
if let conversion  { onCopyConversion?(conversion); return }
if let currency    { onCopyCurrency?(currency); return }
```
Wire to the same copy-to-clipboard body the banner's click handler uses.

### H3. `~/Applications` is never scanned
**`Jetty/Menu/AppIndex.swift:23-32`** · BUG

The scan covers `/Applications`, `/Applications/Utilities`, `/System/Applications`,
`/System/Applications/Utilities`, and
`FileManager.url(for: .applicationDirectory, in: .userDomainMask)`. For a
**non-sandboxed** app (which Jetty is), that last call returns `/Applications`
(the local domain), **not** `~/Applications`. Any app installed for "current user
only" — many Homebrew casks, some drag-installs — is missing from the launcher.
This is the single most user-visible bug in the menu.

**Fix:** explicitly append
`URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Applications")`
and consider `/System/Library/CoreServices`. Canonical source is LaunchServices
(`_LSCopyAllApplicationURLs` / Spotlight) — a later refinement.

### H4. App search is not diacritic-insensitive (nor width-insensitive)
**`Jetty/Menu/AppSearch.swift:39-72`** · BUG/UX

`score()` only `lowercased()`s both sides, so `cafe` ≠ `Café`, `résumé` ≠ `Resume`,
`ñ` ≠ `n`, full-width `Ａ` ≠ `A`. Spotlight/Alfred/Raycast all fold diacritics and
width by default — a real gap on any non-ASCII install.

**Fix:** fold both sides with
`.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)`
and switch the sort to `localizedStandardCompare`.

### H5. App display name is the filename, not the localized `CFBundleDisplayName`
**`Jetty/Menu/AppIndex.swift:42-43`** · BUG/UX

`AppSearchItem.name = url.deletingPathExtension().lastPathComponent`. On a
localized macOS install, `/System/Applications/Calculator.app` shows as
`Calculator`, not `计算器` — so typing pinyin won't match. Brand-renamed apps
(think "  Thing" with a leading space) lose that.

**Fix:** read `CFBundleDisplayName` (then `CFBundleName`) from
`Bundle(url:)`, falling back to the filename. Index both names so the user can
search by either.

### H6. `~/Library/Preferences`-style corruption: `Preferences.offset` is never clamped
**`Jetty/Model/Preferences.swift:158, 245`** · BUG

Every other numeric preference is loaded with `Self.clamp(...)`; `offset` is just
`double(Key.offset, d.offset)`. The Settings slider ranges `-600...600`, but a
hand-edited plist value of `50_000` loads and is applied by `DockLayout` (which
also doesn't clamp). The slider visually pins to −600 while the persisted value
stays enormous. Same gap on the per-display `DockAnchor` override (`inset` is
clamped, `offset` isn't).

**Fix:** `offset = Self.clamp(double(Key.offset, d.offset), -600, 600)`, and
clamp the per-display override too.

### H7. MediaRemote controller path polls a fresh private controller every 5 s
**`Jetty/Menu/NowPlayingWidgetView.swift:12-14` + `MediaRemoteBridge.m:6-7,100-124`** · PERFORMANCE

Each `refresh()` allocates a fresh `MRNowPlayingController`, calls
`beginLoadingUpdates`, polls every 60 ms for up to 1.2 s (20×), then
`endLoadingUpdates` and releases. Heaviest private-API call in the app, at ~5 Hz
for as long as the tile is on screen — even when playback state hasn't changed.
The `dlopen` handle is also never `dlclose`d and `dlsym` is re-resolved every call.

**Fix (incremental):** back off to 10–15 s when paused/idle. **Fix (proper):**
register for now-playing change notifications
(`MRMediaRemoteRegisterForNowPlayingNotifications` + `NotificationCenter`) and
stop polling. Cache the controller and the function pointers (`dispatch_once`).

### H8. Magnified tiles overlap their neighbors (no squish / neighbor-shift)
**`Jetty/Dock/DockTileView.swift:54-60, 227-234` + `DockView.swift:275-291`** · VISUAL

Each tile does `.scaleEffect(scale, anchor: scaleAnchor)` where the anchor is the
edge-facing side, so a tile widens symmetrically along the dock axis. With
`maxScale = 1.5` and `base = 52`, that's +13 pt on each side — past the 8-pt
default spacing — so neighbouring icons visibly clip at the bump's peak. The real
macOS Dock shifts the whole row apart by the integral of the magnification curve.

**Fix:** offset each tile by a neighbor-aware shift (compute the cumulative
magnification from the strip start to the tile center, mirroring `tileCenters`).
The single biggest "feels like the real Dock" win.

### H9. Edge drag-sensor panel swallows clicks/hover at the screen edge
**`Jetty/Dock/DockPanelController.swift:418-467`** · BUG/UX

When auto-hide + edge-hover are on, `updateDragSensor()` installs a 6-pt `NSPanel`
at `.popUpMenu − 1` hugging the visible-frame edge. It registers for file drags
but never sets `ignoresMouseEvents = true`, so it intercepts ordinary
mouse-down/mouse-moved in its 6-pt strip. On a top-edge dock that overlaps
traffic-light buttons; on left/right edges it eats scrollbar arrows and
edge-swipe hotspots. Measurable dead zones at every targeted screen edge.

**Fix:** set `sensorPanel.ignoresMouseEvents = true` (drag tracking is independent
of `ignoresMouseEvents` in AppKit — verify empirically). At minimum drop the
window level to just above app windows instead of `.popUpMenu − 1`.

### H10. `mainScreenUUID()` returns the wrong key under UUID collisions
**`Jetty/Screens/DisplayRegistry.swift:38-44, 56-59`** · BUG

`rebuild()` disambiguates duplicate hardware UUIDs by suffixing `#2`, `#3`, …, so
both displays stay in `screensByUUID`. But `mainScreenUUID()` returns
`Self.key(for: main)` — the **raw, undisambiguated** UUID. If `NSScreen.main` is
the *second* of two displays that share a UUID, the lookup returns the *first*
screen. In `.mainOnly` scope the user's main dock renders on the wrong monitor.

**Fix:** walk the dictionary and return the key whose value `=== main`:
```swift
func mainScreenUUID() -> String? {
    guard let main = NSScreen.main else { return screensByUUID.keys.first }
    return screensByUUID.first(where: { $0.value === main })?.key
}
```

### H11. Auto-reveal "ghost fires" when the pointer leaves the screen mid-dwell
**`Jetty/Dock/DockPanelController.swift:192-217`** · BUG

In `handleMouseMoved`, the off-screen (seam) branch only cancels `revealWork` when
`pointerCrossedDockEdge(point, band: 24)` is true. If the pointer was in the
reveal zone (so a 60 ms reveal is queued) then moves off-screen *sideways* onto
another display rather than past the dock edge, the function returns without
touching `revealWork`. The pending reveal fires anyway, popping the dock on a
screen the pointer has already left.

**Fix:** cancel any pending reveal at the top of the off-screen branch when
you're not going to reveal.

### H12. Pomodoro completes instantly after the Mac sleeps
**`Jetty/Widgets/PomodoroTimer.swift:31,57-68`** · BUG

`endDate` is absolute. While asleep, `Timer` doesn't fire, but on wake the first
`tick()` calls `updateRemaining(now:)` with the post-sleep clock — so 10 minutes
left + a 1-hour sleep → `endDate.timeIntervalSince(now)` is negative → clamped to
0 → the session instantly "completes" and plays the Glass sound. A user who
closes the laptop mid-session loses the timer every time. No persistence across
restart either, so an updater relaunch loses it too.

**Fix:** observe `NSWorkspace.willSleepNotification`/`didWakeNotification` → on
wake, `endDate = Date().addingTimeInterval(remainingAtSleep)`. Persist
`(endDate, remaining, isRunning)` to `UserDefaults` and restore in `init`.

### H13. Network byte counters are 32-bit and wrap at 4 GB
**`Jetty/Widgets/SystemStats.swift:99-102`** · BUG

`getifaddrs`/`AF_LINK`'s `ifa_data` points at `struct if_data` whose
`ifi_ibytes`/`ifi_obytes` are `u_int32_t` (4 GB). On a gigabit link a sustained
download wraps in ~32 s. The wrap is caught by `LiveSystemStats.throughput`
(current < previous → 0), so the live graph shows a periodic dip to zero during
every large transfer — visually broken for what should be the marquee case.

**Fix:** switch to `sysctl` with `NET_RT_IFLIST2`, which returns
`struct if_msghdr2` with 64-bit counters. Matches `netstat -i`/Activity Monitor.

### H14. `DateFormatter` allocated on every clock render
**`Jetty/Widgets/ClockFormatter.swift:22,27,30,46-52`** · PERFORMANCE

`formatter(template:locale:timeZone:)` allocates a new `DateFormatter` per call;
`lines(for:)` makes up to 3 calls. With `clockShowSeconds` on, the `ClockWidgetView`
`TimelineView` fires every 1 s, and each world-clock tile adds 3 more. Easily 6+
`DateFormatter` allocations per second on the main thread; `DateFormatter` is
notoriously expensive to construct. `WorldClockWidgetView.timeZone`
(`WorldClockWidgetView.swift:10-12`) recomputes `TimeZone(identifier:)` every
render too.

**Fix:** cache formatters in a small `private static` dictionary keyed by
`template|locale|timezone`. Cache the resolved `TimeZone` and recompute only when
`preferences.worldClockTimeZone` changes.

### H15. Weather network/API errors leave the widget spinning forever
**`Jetty/Widgets/WeatherService.swift:48-65`** · BUG

`URLSession.shared.dataTask { data, _, _ in }` throws away `response` and `error`.
Network down, Open-Meteo 4xx/5xx, or an error JSON → `Self.parse` returns nil →
`snapshot` is never set → `WeatherWidgetView` keeps showing `ProgressView()` with
no indication anything failed or that retries stopped. If the first request
fails, the user is permanently stuck on a spinner.

**Fix:** surface `@Published var lastError`; check `HTTPURLResponse.statusCode`;
keep showing the stale snapshot on refetch failure; render a `cloud.slash` glyph
+ last-known temp when offline.

### H16. `DockStore` icon-cache / `TileAccent` cache grow unboundedly for app lifetime
**`Jetty/Menu/JettyMenuModel.swift:91-100` + `Jetty/Common/TileAccent.swift:10,34`** · PERFORMANCE/MEMORY

`iconCache: [String: NSImage]` accumulates a full-res `NSImage` (~1 MB each) for
every app ever seen, no eviction. `TileAccent.cache` is a never-cleared mutable
static and allocates a fresh `CIContext` on **every** call (`CIContext` is
documented as expensive). Over a long lifetime both leak meaningfully.

**Fix:** swap for `NSCache` (auto-evicts under pressure) or the existing
`LRUImageCache`/`LRUImageCacheByKey` in `Common/`. Cache one shared `CIContext`
in a `static let`. Add `clearCache()` and call from `DockStore` on item changes.

### H17. `NowPlayingService.inFlight` can stick `true` forever
**`Jetty/Widgets/NowPlayingService.swift:19,22-29`** · BUG

`refresh()` sets `inFlight = true`, then relies on the bridge completion *always*
firing. On the controller path, if a half-present private framework never
delivers, `inFlight` is never reset → every subsequent refresh is a silent no-op
→ the tile freezes forever. (C4's crash class is the worst case; this is the
hang case.)

**Fix:** add a safety timeout
`DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in if self?.inFlight == true { self?.inFlight = false } }`.

### H18. `addLink()` mangles non-HTTP URL schemes
**`Jetty/Settings/ItemsView.swift:201-203`** · BUG

`let normalized = raw.contains("://") ? raw : "https://\(raw)"`. A user typing
`mailto:foo@bar.com` gets `https://mailto:foo@bar.com`. Same for `message:`,
`facetime:`, `maps:`, `app-prefs:`. Branching on `://` only works for
hierarchical URLs.

**Fix:** detect an existing scheme with `URL(string: raw)?.scheme != nil` (or a
regex `^\w+:`). Only prepend `https://` if no scheme is present. Consider an
allow-list to reject `javascript:`/`file:`.

### H19. `ColorHex.hexString` can produce invalid output for wide-gamut/HDR colors
**`Jetty/Model/ColorHex.swift:35-38`** · BUG

`Int((c.redComponent * 255).rounded())`. After `usingColorSpace(.sRGB)` components
*should* be `[0,1]`, but for extended-range sources they can exceed 1.0.
`Int(1.5 * 255) = 382`, then `String(format:"#%02X%02X%02X", 382, …)` produces an
invalid hex string that round-trips through `NSColor(hex:)` as failure →
`.clear`. A picked color silently becomes transparent. (Bonus: alpha is discarded
on write — see L9.)

**Fix:** clamp each component to `0...1` before scaling.

### H20. WindowPeek's 1-second screen-capture timer is expensive
**`Jetty/Windows/WindowPeek.swift:29-31`** · PERFORMANCE

`Timer(timeInterval: 1.0, repeats: true)` captures every visible window of the
hovered app every second while the popover is up. `SCShareableContent.current` +
an `SCScreenshotManager.captureImage` per window is real CPU/GPU work, running
even when nothing on screen changed. (`WindowLister.windows(forPID:)` is also
called twice per peek show — `WindowPeekController.swift:30` + `WindowPeek.swift:26`.)

**Fix:** raise to ~3 s, pause when `model.thumbnails` would be unchanged
(compare window-list bounds), or invalidate on `NSWorkspace.didActivateApplication`.
Pass the pre-fetched window list into `model.load` to avoid the double fetch.

### H21. Power commands / automation silently fail when permission is denied
**`Jetty/Menu/PowerCommands.swift:78-84` + `Jetty/Menu/JettyMenuController.swift:127-130`** · UX/SECURITY

When the user denies Automation permission, `NSAppleScript.executeAndReturnError`
returns an error and the only feedback is `NSLog(...)`. The menu has already
closed, so the user gets **no** indication their Sleep / Toggle Dark Mode didn't
work — and no path to retry. The TCC prompt may pop up *after* the menu is gone,
leaving the user confused.

**Fix:** don't `close()` until the script resolves. On error, surface an in-menu
banner ("Automation permission denied — open System Settings?") with a deep link
to `x-apple.systempreferences:com.apple.preference.security?Privacy_Automation`.

### H22. "Lock Screen" only sleeps the display — doesn't always lock
**`Jetty/Menu/PowerCommands.swift:86-93`** · BUG/SECURITY

The comment is honest, but the user-facing title is "Lock Screen". The impl is
`pmset displaysleepnow`, which only locks if "Require password after sleep" is
immediate. With the very common "5 minutes" setting, the screen turns off
**without locking** and a passerby can wake it and read the session.

**Fix:** invoke the Screensaver engine instead — what ⌃⌘Q and the menu-bar
Lock-Screen item use:
`/System/Library/CoreServices/ScreenSaverEngine.app/Contents/MacOS/ScreenSaverEngine`.

### H23. Trash `DispatchSource` cancel-handler races fd reuse
**`Jetty/Apps/TrashMonitor.swift:14-38`** · BUG

The cancel handler reads `self?.fileDescriptor` at *cancel time*, not capture
time. Sequence that breaks it: `stop()` → `source.cancel()` (async); `start()`
runs immediately → opens a new fd → assigns `fileDescriptor = newFd` → installs
the new source; the *old* cancel handler finally runs → reads the now-overwritten
`fileDescriptor` → `close(newFd)`. The new monitor watches a closed fd, and the
integer may be reused by an unrelated `open()`.

**Fix:** capture the fd by value in the closure: `let fd = descriptor; src.setCancelHandler { if fd >= 0 { close(fd) } }`. Don't store `fileDescriptor` on `self`
for closing. Add `deinit { stop() }` mirroring `EdgeHoverMonitor`.

### H24. `NSWorkspace.didWakeNotification` observer leaks; never removed
**`Jetty/Dock/DockController.swift:119-122`** · BUG

The block observer is registered but the returned token is discarded, so it can
never be removed in `teardown()`. `[weak self]` prevents a cycle, but the
observer (and block) stay registered forever — across `teardown`/`start` cycles,
every relaunch stacks another. In tests this also causes callbacks into
half-torn-down controllers.

**Fix:** store the token; `removeObserver` in `teardown`.

### H25. `AppIndex.reload()` has no in-flight tracking; rapid opens race
**`Jetty/Menu/AppIndex.swift:14-19`** · BUG/PERFORMANCE

Called on every menu open with no cancellation. Two overlapping scans race; the
**last to finish** wins, which isn't necessarily the latest. Each scan re-stats
every `.app` in the scan dirs (hundreds on a dev machine).

**Fix:** add `inFlight` flag or use a cancellable `Task`; only publish the latest
scan. Better: refresh incrementally on `didLaunchApplication` /
`didTerminateApplication` instead of re-scanning everything per open.

---

## Medium

### M1. App-icon resolution on the main thread on every running-app change
**`Jetty/Dock/DockModel.swift:71-90, 156-190`** · PERFORMANCE

`rebuild` is called on every launch/terminate/activate/deactivate/hide/unhide and
loops all tiles calling `icon(for:)` — on a cache miss `NSWorkspace.shared.icon(forFile:)`
is a synchronously blocking, LaunchServices-touching call. `relayoutPanels()`
also runs on every activate/deactivate even though panel frames only depend on
tile kinds/counts, which don't change on a plain focus flip.

**Fix:** resolve first-time icons on a background queue and merge back to main.
Diff slot/tile structure and skip `relayoutPanels()` when only `isRunning`/
`isActive` flags changed (extend the `prefSig` idea to model changes).

### M2. Diagnostic `NSLog` calls left in production paths
**`Jetty/Dock/DockController.swift:219-221, 241` + `DockPanelController.swift:166-168`** · CLEANNESS

Three `NSLog("[Jetty] …")` calls marked "TEMP DIAGNOSTIC (remove once confirmed)"
are still in. `reconcilePanels` runs on every screen change and `reveal` on every
reveal — they spam `system.log`/Console.app, including `NSStringFromRect` formatting.

**Fix:** wrap in `#if DEBUG` or switch to `os_log` with `.debug`.

### M3. `panel.invalidateShadow()` runs on every non-animated relayout
**`Jetty/Dock/DockPanelController.swift:410`** · PERFORMANCE

`applyRevealState(animated:)` is called from `layoutForCurrentState()` on every
`relayoutPanels()` → which fires on every running-app notification. Each call
ends with `panel.invalidateShadow()`, forcing shadow recomputation for a
transparent, hasShadow panel. During cmd-tab storms, dozens of shadow
recomputations/sec per panel.

**Fix:** only invalidate when the reveal/hidden state or frame actually changed.

### M4. Live stats timer and widget TimelineViews keep running while the dock is hidden
**`Jetty/Dock/DockController.swift:176-179` + per-widget `TimelineView`s** · PERFORMANCE

`updateLiveStats()` gates the sampler on `!panels.isEmpty` but not on whether any
panel is *revealed*. The per-widget `TimelineView`s (Clock 1 s/30 s, WorldClock,
Weather 900 s, NowPlaying 5 s) also keep firing while the panel is hidden via a
layer transform — ~95% of the time for an auto-hiding dock. 95% of the timer /
CPU / MediaRemote work is wasted.

**Fix:** gate on `panels.values.contains { $0.isRevealed }`. Expose `isRevealed`
to `DockView` and swap/tear down the periodic schedules while hidden. At minimum
make the NowPlaying poll a no-op while hidden.

### M5. All sampler syscalls run on the main thread every 2 s
**`Jetty/Widgets/LiveSystemStats.swift:62-93`** · PERFORMANCE

`Timer` on `RunLoop.main`; `sample()` synchronously calls `getloadavg`,
`host_statistics64`, `getifaddrs`, and (every 15th tick) `IOPSCopyPowerSourcesInfo`
on the main thread — `getifaddrs` can block briefly. This is exactly the kind of
thing that produces micro-hitches while the dock animates.

**Fix:** sample on `DispatchQueue.global(qos: .utility)`, hop to main only to
assign `@Published` properties.

### M6. `mach_host_self()` leaks a Mach port right every call
**`Jetty/Widgets/SystemStats.swift:68, 75`** · LEAK

`host_statistics64(mach_host_self(), …)` — each `mach_host_self()` returns a send
right and nothing calls `mach_port_deallocate`. Called every 2 s, this leaks a
port reference per sample. Ports are finite per-task resources.

**Fix:** cache `mach_host_self()` once for the task lifetime, or
`mach_port_deallocate(mach_task_self_, host)` after the call.

### M7. Edge-hover monitor fires on every mouse move with no throttle
**`Jetty/Dock/EdgeHoverMonitor.swift:18-28` + `DockController.swift:61-64`** · PERFORMANCE

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
**`Jetty/Screens/DockLayout.swift:41-43` + `DockController.swift:214-245`** · UX

When the user removes every item, `contentSize(tiles: [])` falls back to the
1-tile placeholder size — a real glass strip with nothing inside, still
revealing/hiding on edge hover. Feels unfinished.

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

### M10. Selected row text is hard-coded white regardless of tint
**`Jetty/Menu/JettyMenuView.swift:174-176`** · VISUAL/A11Y

`foregroundStyle(selected ? Color.white : Color.primary)` with a light tint
(white, yellow, light pink — fully supported in Appearance) → white-on-near-white
selected row. WCAG-failing.

**Fix:** derive the foreground from tint luminance (`isLight ? .black : .white`).

### M11. No hover-to-select on result rows; web-search row hidden when apps match
**`Jetty/Menu/JettyMenuView.swift:33-36, 152-178`** · UX

The selection is driven only by keyboard + click (no `.onHover`), so a mouse user
arrowing to row 3 then hovering row 7 sees the highlight stuck on row 3. And the
web-search fallback only appears when `results.isEmpty` — common case
("world cup 2026" with two unrelated app matches) gives no path to web search
without navigating past the apps. Every competitor keeps "Search the web for X"
as the **last** row regardless of matches.

**Fix:** add `.onHover { if hovering { model.selectedIndex = index } }`. Always
show the web-search row at the bottom when the query is non-empty.

### M12. Currency formatting uses unit-converter precision (4 dp) and ISO codes
**`Jetty/Menu/JettyMenuModel.swift:70`** · VISUAL/UX

`"\(UnitConverter.format(value)) \(parsed.to)"` → `100 USD to EUR` shows
`91.2345 EUR`. Four decimals is wrong for money (should be 2, or 0 for JPY/KRW),
and the ISO code shows instead of `€`.

**Fix:** `NumberFormatter(currencyStyle: .currency)` with `currencyCode = parsed.to`.

### M13. Recents store does a `stat()` syscall per entry per keystroke
**`Jetty/Menu/RecentAppsStore.swift:36-42` + `JettyMenuModel.swift:57`** · PERFORMANCE

`recentsProvider?()` → `recentItems()` → UserDefaults decode →
`compactMap { FileManager.default.fileExists(atPath:) }` — up to 8 `stat()` calls
on the main thread on every character typed. Noticeable on a network homedir.

**Fix:** cache `recentItems()` in the model, invalidated only on `record(...)`.
Have `RecentAppsStore` publish via Combine.

### M14. Calculator/conversion/currency: no `⌘C` to copy the answer
**`Jetty/Menu/JettyMenuView.swift:84-110`** · UX

Click-to-copy works. `⌘C` doesn't (would copy nothing or the selected row's
text). `⌘⇧C` would be the natural binding. Pairs with H2.

### M15. Local key monitor swallows Escape/Return/Up/Down app-wide
**`Jetty/Menu/JettyMenuController.swift:147-158`** · UX/BUG

`NSEvent.addLocalMonitorForEvents(.keyDown)` is app-global. If Settings (or an
alert) is focused behind the menu, Esc/Return/↑/↓ are eaten before reaching it.
No `Cmd+Return` (force web search), no `Cmd+1..9` (jump to result N).

**Fix:** `guard panel.isKeyWindow else { return event }` at the top. Add
`Cmd+1..9` and `Cmd+Return`.

### M16. Power row is mouse-only; 9 pt labels; no typed access
**`Jetty/Menu/JettyMenuView.swift:180-197`** · UX/A11Y

The 6 power buttons are SwiftUI `Button`s with no `@FocusState` — unreachable by
keyboard. Typing "sleep" doesn't surface a Sleep command-row. `Text(title).font(.system(size: 9))`
is below the system "small" and doesn't participate in Dynamic Type.

**Fix:** add `MenuCommand` cases for each power command (so they're typed), give
the row a `@FocusState`/Tab stop, use `.caption2` or `.system(size: 10, weight: .medium)`.

### M17. No empty / no-results state in the menu
**`Jetty/Menu/JettyMenuView.swift:141-164`** · UX

Empty query with no recents/apps → blank scroll area. Non-empty query with no
matches → only the web-search row at the bottom. Spotlight/Alfred show a clear
"No Results" row. Reads as a bug to the user.

**Fix:** add a centered "No matching apps" / "Jetty hasn't found any apps yet"
empty state.

### M18. Selected index resets to 0 whenever results shrink
**`Jetty/Menu/JettyMenuModel.swift:59`** · UX

Arrowing to row 5 of 10, then typing one more char that narrows to 8 → selection
jumps to 0. Spotlight/Alfred preserve the selection by id.

**Fix:** track selection by `AppSearchItem.id`; on recompute, reselect the
previously-selected id if still present.

### M19. `appToRestoreOnClose` can be nil (frontmost quit) → Jetty left frontmost
**`Jetty/Menu/JettyMenuController.swift:25, 73`** · BUG

If the captured frontmost app quits while the menu is open, `close()` falls
through `if let restore` and does nothing — leaving Jetty (an `LSUIElement`
accessory) as "frontmost". Users see no menu bar until they click another app.

**Fix:** fall back to activating Finder when `restore` is nil.

### M20. Accessibility: widgets/tiles expose only a static label
**`Jetty/Dock/DockTileView.swift:41-44, 75-89` + all of `Widgets/`** · A11Y

`.accessibilityValue` is hard-coded to `"Running"`/`""`. For info widgets — clock
time, battery %, CPU/RAM, temp, track, pomodoro remaining — the visible info is
**not** exposed to VoiceOver at all. A VoiceOver user only hears "Clock". Zero
`accessibility` calls exist anywhere under `Widgets/`. No `.accessibilityAction(.default)`
on tiles; SwiftUI's auto-connection between `.onTapGesture` + `.isButton` is
unreliable.

**Fix:** each widget publishes its display string as `.accessibilityValue` (e.g.
Battery → `"53 percent, charging"`). Add `.accessibilityAction(.default) { onTap() }`
and a hint per kind. `.accessibilityElement(children: .ignore)`.

### M21. Settings accessibility gaps
**`Jetty/Settings/GeneralView.swift`, `AppearanceView.swift`, `AngleDial.swift:45-46`, `MenuView.swift`** · A11Y

Sliders expose `.accessibilityValue` as a bare percentage, not "52 pt". `AngleDial`
is drag-only — no stepper, no `accessibilityAdjustableAction`. Menu glyph buttons
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
**`Jetty/Settings/DisplaysView.swift:66-73`** · PERFORMANCE

`NSScreen.screens` + `registry.key(for:)` (which calls `CGDisplayCreateUUIDFromDisplayID`)
on every body recompute — including every slider drag. The array identity changes
each call, so SwiftUI's diff treats the `ForEach` as fully invalidated.

**Fix:** cache entries in `@State`, refresh on `didChangeScreenParametersNotification`.

### M24. `ItemsView.row` loads icons via `NSWorkspace`/`NSImage` on every render
**`Jetty/Settings/ItemsView.swift:118-122, 141`** · PERFORMANCE

`NSImage(contentsOfFile:)` (sync disk read) and `urlForApplication(withBundleIdentifier:)`
(LaunchServices query) per row per render. 30+ items × every prefs tick = janky.

**Fix:** wrap in a cache keyed by `item.id + customIconPath + bundleIdentifier`.

### M25. PermissionsView polls every 2 s
**`Jetty/Settings/PermissionsView.swift:58`** · PERFORMANCE

`Timer.publish(every: 2).autoconnect()` calls `AXIsProcessTrusted()` and
`CGPreflightScreenCaptureAccess()` for as long as the tab is open.

**Fix:** drop to ~5 s, or re-check on `didActivateApplicationNotification` (the
user came back from System Settings). Pause when the window loses key.

### M26. Folder stack loads icons for all entries *before* the 128-entry prefix
**`Jetty/Stacks/FolderStack.swift:28-44`** · PERFORMANCE

The `prefix(limit)` cap is applied after mapping every URL through
`NSWorkspace.shared.icon(forFile:)`. A 10 000-file folder does 10 000 icon loads
before trimming to 128.

**Fix:** sort first (using only `name` + `isDirectory` from one
`resourceValues` call), `.prefix(limit)`, then load icons only for the 128 kept.

### M27. `AppearancePreset.decode` never reports a bad file
**`Jetty/Model/AppearancePreset.swift:118-127` + `AppearanceView.swift:132-135`** · UX/BUG

`init(from:)` uses `decodeIfPresent ?? default` for every field, so an empty `{}`
or `{"foo":"bar"}` produces a valid "Imported" preset full of defaults. The error
"That file isn't a Jetty or Zap theme" is unreachable. A user importing a totally
wrong file gets a silent theme switch.

**Fix:** require at least one recognized key, else return nil.

### M28. `apply(_:)` doesn't validate hex strings
**`Jetty/Model/Preferences.swift:313-334`** · BUG

Imported/edited presets can put any string into `tintHex`/`gradientHex`/
`indicatorHex`/`glyphHex`. `Color(hexString:)` falls back to `.clear`, so a
malformed preset silently paints the dock transparent.

**Fix:** validate each hex against `NSColor(hex:) != nil`; fall back to the default.

### M29. Clock 30 s cadence can lag up to 30 s
**`Jetty/Widgets/ClockWidgetView.swift:11-13` + `WorldClockWidgetView.swift:15`** · VISUAL

`TimelineView(.periodic(from: .now, by: 30))` starts from `.now` and ticks every
30 s — it does not align to the minute boundary. Launch at 10:00:20 and the
displayed minute rolls over to `:01` at 10:01:20, lagging the true time by up to
30 s. For a clock tile, the "wrong minute" shows a third of the time.

**Fix:** drive cadence by a schedule that snaps to the next whole minute, or
run a 1 s `TimelineView` and gate re-rendering on the minute changing.

### M30. Battery widget: no low-battery emphasis; charging always shows 100% glyph
**`Jetty/Widgets/BatteryWidgetView.swift` + `SystemStats.swift:39-48`** · VISUAL/UX

`batterySymbol` returns `"battery.100.bolt"` for *all* charging states — 5 %
plugged in shows a full-battery glyph. No color change at low battery
(`battery.0` stays `.primary`).

**Fix:** tint red below 20 %; show `battery.N` with a separate `bolt.fill`
overlay.

### M31. Currency API leaks the user's IP to a third party on every menu open
**`Jetty/Menu/CurrencyService.swift:25` + `JettyMenuController.swift:52`** · PRIVACY

`ensureFresh()` hits `https://api.frankfurter.app/latest?from=USD` (third party)
on every `show()`, no opt-in. The first time the user opens the menu, their IP
goes to frankfurter.app. `AGENTS.md` doesn't flag this.

**Fix:** fetch lazily only when `computeCurrency()` parses a query but rates are
empty. Add an on/off toggle in Settings.

### M32. Currency rates not persisted; no offline/stale indication; no timeout
**`Jetty/Menu/CurrencyService.swift:14-36`** · UX

Every app launch starts with `rates = [:]`; offline-at-launch = unavailable until
the 6 h cache ticks. `parseRates` accepts any NSNumber including `0`/negatives →
a malformed payload makes `convert` divide by zero → `"inf EUR"`. `URLSession.shared`
defaults to a 60 s timeout.

**Fix:** persist last-known-good rates to `UserDefaults` with a timestamp; show
as "stale" past 48 h; add a 10 s timeout; in `parseRates`, skip rates `<= 0` or
non-finite; in `convert`, return nil if either rate is zero/non-finite.

### M33. Pomodoro completion: only a sound, no notification
**`Jetty/Widgets/PomodoroTimer.swift:57-63`** · MISSING

If the dock is hidden, another app is focused, or the system is muted, the user
has no idea their Pomodoro finished. `mm:ss` also overflows the tile for sessions
≥ 60 min (`String(format: "%d:%02d", …)` — `120:00` is 5 chars, no
`minimumScaleFactor`).

**Fix:** post a `UNUserNotification` ("Pomodoro complete — take a break!"). For
the label, switch to `H:MM:SS` (or `2h00m`) past 60 min, or
`.lineLimit(1).minimumScaleFactor(0.5)`.

### M34. `toggleAllDocks` flips each panel independently
**`Jetty/Dock/DockController.swift:604` + `DockPanelController.swift:178-180`** · UX

The global hotkey calls `toggle()` on each panel. Mixed states (panel A revealed
because the pointer is on its screen, panel B hidden) → the hotkey swap-hides A
and swap-reveals B — almost certainly not the user's intent.

**Fix:** define toggle as "if ANY panel is revealed, hide all; else reveal all".

### M35. AppleScript power commands: no per-command confirmation wording
**`Jetty/Menu/JettyMenuController.swift:102-111`** · UX

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

### M37. `AppLauncher.resolvedURL` doesn't refresh stale bookmarks (inconsistent with `DockStore`)
**`Jetty/Apps/AppLauncher.swift:71-73` vs `Jetty/Store/DockStore.swift:57-67`** · BUG

`DockStore.resolvedURL(forItemID:)` refreshes stale bookmarks and writes back.
`AppLauncher.resolvedURL` (used on every tile click) bypasses that — so a moved
app resolves correctly once, but the stale bookmark is never written back to
`dock.json`. A later launch through a different path keeps hitting the stale
bookmark.

**Fix:** route `AppLauncher.open` through `DockStore.resolvedURL(forItemID:)`.

### M38. SystemDock re-assert can thrash `killall Dock`
**`Jetty/SystemDock/SystemDockController.swift:37-101`** · BUG/UX

`reassertIfManaging()` has no debounce; wake + screen-change can fire nearly
simultaneously and issue two `killall Dock` calls within ~1 s, on some machines
making the Dock thrash or flash. If Jetty is force-quit between `isManaging = true`
and `restartDock()` returning, the system is left in the managed state with no
Jetty running.

**Fix:** coalesce `killall Dock` calls (1 s `DispatchWorkItem` debounce). Add a
launch-time auto-recovery: if a stale `isManaging=true` is detected and the user
didn't opt in this session, restore. Add a "Force restore System Dock" menu item.

### M39. `BoingBallDecoration` / `TileAccent` static mutable globals aren't thread-safe
**`Jetty/Common/BoingBallDecoration.swift:99-100` + `TileAccent.swift:10`** · ENHANCEMENT

Mutable statics touched from `body` only because today is main-thread. Moving
toward Swift 6, these race if any view ever composes on a background queue.

**Fix:** wrap in a `final class` actor or `@MainActor` singleton.

### M40. Force-try / force-unwrap on constructed URLs
**`Jetty/Updates/GitHubReleaseClient.swift:42`, `Jetty/Hotkeys/AccessibilityAuthorizer.swift:29`** · BUG

`URL(string: "https://api.github.com/repos/\(owner)/\(repo)/…")!` traps if
`owner`/`repo` ever contain URL-breaking chars. Safe today (constants), but
violates the repo's "no force-unwraps outside tests" rule.

**Fix:** `guard let url = URL(string: …) else { throw … }`.

### M41. `UnitConverter` dead `"` alias; `in` reserved so `10 m to in` fails
**`Jetty/Menu/UnitConverter.swift:32, 49-50, 63`** · BUG

The regex `[\w°]+` never matches `"`, so the registered `"` (inch) alias is
unreachable. And because `in` is the separator, `10 m to in` returns nil (units
only register `inch`/`inches`).

**Fix:** extend the regex to `[\w°"]+`; register `in` as a *target* unit only.

---

## Low / polish

- **L1 — `CarbonHotkey`** (`Hotkeys/CarbonHotkey.swift:57-65`): one
  `InstallEventHandler` per instance; `Unmanaged.passUnretained(self)` as
  `userData` is only safe if `deinit` runs on the main thread. Use a single
  shared app-wide handler that just `RegisterEventHotKey`s per instance.
- **L2 — `SemanticVersion`** (`Updates/SemanticVersion.swift:34-39`): main
  components accept leading zeros (`01.02.03`) but pre-release doesn't —
  inconsistent with SemVer §2.3. Reject or document.
- **L3 — `releaseNotes()`** (`Updates/GitHubRelease.swift:55-60`): truncation by
  `String.Index` can split an extended grapheme cluster on emoji-heavy notes.
- **L4 — `UpdateChecker.start()`** (`Updates/UpdateChecker.swift:91-101`): no
  jitter/back-off; a relaunch wave can hit GitHub's 60/h/IP unauthenticated
  limit. Add `X-RateLimit-Remaining` awareness + a randomized initial delay.
- **L5 — `localizedCaseInsensitiveCompare` on every keystroke**
  (`AppSearch.swift:22,31`, `AppIndex.swift:60`): ICU collation on every char.
  Pre-sort once in `AppIndex`; cache the empty-query result.
- **L6 — `AppSearch.score` recomputes `query.lowercased()` 3×**
  (`AppSearch.swift:39-49`): hoist out of the loop.
- **L7 — Recents always shown, no clear/remove**
  (`JettyMenuModel.swift:81-89`): no `×`, no "Clear recents", no section header
  distinguishing recents from the alphabetical list. Incognito mode missing.
- **L8 — Web search is Google-only** (`JettyMenuController.swift:117-124`): no
  preference for DuckDuckGo/Brave/Kagi/system engine.
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
  `.liquidGlass`/`.glassClear`/`.glassTinted` all become `.hudWindow`. The
  distinction the user picked is invisible.
- **L15 — `VisualEffectBlur` forces `.state = .active`**
  (`Common/VisualEffectView.swift:13,19`): when the panel loses key the blur
  still renders active — slight mismatch with system panels.
- **L16 — `DisplayScope.mainOnly` copy is misleading**
  (`Settings/DisplaysView.swift:21-23`): "whichever currently has keyboard focus"
  is wrong — it's the `NSScreen.main` (key-window screen). Reword.
- **L17 — World-clock zone label gives region, not city** (`WorldClockWidgetView.swift:42-45`):
  `US/Eastern` → `Eastern`; no day/night glyph.
- **L18 — Weather `(0,0)` sentinel + no city name shown**
  (`WeatherWidgetView.swift:27-35`): anyone near the Gulf of Guinea can't
  configure it; the tile never shows *which* location. Reverse-geocode the name.
- **L19 — Weather: only current temp, no rich data** (`WeatherService.swift`):
  Open-Meteo returns `apparent_temperature`, humidity, wind, daily hi/lo for the
  same no-key call — ignored. Surface in a tooltip + accessibility value.
- **L20 — System monitor: network is down+up combined**
  (`SystemMonitorWidgetView.swift:87`): data is already separate; draw two lines.
- **L21 — `normalizedLoad()` is load average, not CPU %** (`SystemStats.swift:54-59`):
  takes 30–60 s to converge, can exceed 100 %. Compute true CPU % from
  `host_processor_info` (HOST_CPU_LOAD_INFO) like `top`.
- **L22 — `dlopen` handle never closed; `dlsym` re-resolved per call**
  (`MediaRemoteBridge.m:71-79`): `dispatch_once` both the handle and fn pointer.
- **L23 — `WindowPeekView` nests Buttons inside Buttons**
  (`Windows/WindowPeek.swift:122-138, 145-172`): SwiftUI's nested-button
  hit-testing is unreliable — sometimes both fire. Use overlaid tap gestures.
- **L24 — Custom icon path won't follow moves** (`Settings/ItemsView.swift:88-95`):
  stores a bare path; if the user moves the source file, the icon vanishes. Copy
  into `Application Support/Jetty/icons/<id>.png` or bookmark it.
- **L25 — No "Reset to defaults" anywhere in Settings** (`Settings/*View.swift`):
  wild experimentation is one-way. Add per-pane reset buttons; `Preferences.Default`
  already centralizes values.
- **L26 — No user-saved presets** (`Settings/AppearanceView.swift:80-95`):
  built-ins can be Applied and Exported/Imported, but there's no in-app "My
  preset" for one-click re-apply.
- **L27 — No preset/widget previews in Settings**: configure blind; render a
  small faux dock (3 tiles) per preset, a live preview per widget.
- **L28 — `ItemsView.row` displays wrong state when display disabled**
  (`Settings/DisplaysView.swift:30-37`): toggling "Disable dock" hides the
  controls but retains the override; re-enabling surprises the user. Add a
  "Reset to global default" button.
- **L29 — `FolderStackView.header` back button too small**
  (`Stacks/FolderStack.swift:186-200`): ~12 pt glyph, below the ~20 pt HIT min.
  Wrap in `.frame(24×24).contentShape(Rectangle())`.
- **L30 — `FolderStackController` Escape requires Jetty frontmost**
  (`Stacks/FolderStackController.swift:110-113`): the popover is
  `.nonactivatingPanel`, so the previously-focused app keeps key — Esc dismisses
  that app's modal, not the popover. Click-outside still works; document.
- **L31 — `runningApplication(bundleIdentifier:)` fallback defeats `indexByBundle`**
  (`RunningAppsModel.swift:83-85`): the full-scan fallback re-introduces exactly
  what the index avoids. Drop it.
- **L32 — `BookmarkResolver` uses `[]` options** (`Store/BookmarkResolver.swift:11-26`):
  fine non-sandboxed, but a future App-Store variant will silently break without
  `startAccessingSecurityScopedResource` at call sites. Add TODOs.
- **L33 — `seedDefaultItems` is English-only** (`DockController.swift:668-683`):
  localize the display names; detect a default browser when Safari is absent.
- **L34 — `DockContextAction.id = UUID()`** (`Dock/DockContextAction.swift:7`):
  context menu rebuilt per right-click mints new ids → no animation continuity.
  Use `id: \.title` (titles are unique).
- **L35 — `DockLayout.contentSize(tiles: [])` returns the 1-tile placeholder**
  (`Screens/DockLayout.swift:41-43`): root cause of M8. Return `.zero` and let
  the caller decide on a placeholder.
- **L36 — `MediaRemoteBridge` legacy `dlopen` is exemplary but the controller
  path doesn't match it** (`MediaRemoteBridge.m`): the contrast highlights that
  the fail-closed promise is only half-kept. See C4.
- **L37 — `dockDefaults?.synchronize()` is deprecated/best-effort**
  (`SystemDockController.swift`): the relaunched Dock may briefly show the user's
  original delay. Document.
- **L38 — `AppLauncher.openApplication` always launches, never switches**
  (`JettyMenuController.swift:43-47`): if the app is already running, this may
  open a new window or do nothing useful. Switch-if-running like dock tiles do.
- **L39 — No "drag result row to dock to pin"** (`JettyMenuView.swift`): menu rows
  aren't draggable. Common Alfred→dock interaction.
- **L40 — No settings ⌘F search**: 8 tabs, ~60 controls — discoverability is
  rough. macOS users expect it.
- **L41 — `UnitConverter` missing common families** (`UnitConverter.swift:51-88`):
  no time/duration, area, pressure, energy, angle, fuel, data rate, bits/bytes
  distinction.
- **L42 — `hexString`/`init?(hex:)` reject bare-word colors** (`red`): CSS
  keywords are common in hand-edited themes.

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
overrides + settings UI.) IDEA-2 from `GPT-is-awesome.md`.

### Edge reveal "heat map"
A brief, optional glow in the reveal band after failed edge attempts — teaches
users where the dock lives without leaving a permanent sliver. IDEA-1.

### Dock "breathing" on wake
After wake/display reconnect, pulse the dock once to communicate it reclaimed the
system-Dock state and restored placement. IDEA-3.

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

---

## What's done well

To balance the punch list — the architecture is sound and most of this is
polish, not rework:

- **The core-dock permission-free promise is real.** No Accessibility, no
  `CGEventTap`, no global *key* monitor, no private APIs in the core path.
  `CarbonHotkey`, `NSWorkspace`, `RegisterEventHotKey`, mouse-only global
  monitor. Excellent discipline — and exactly the load-bearing design decision
  `AGENTS.md` calls out.
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
- **`UpdateDownloader.sanitizedFileName`** strips control chars, separators,
  rejects `.`/`..`/empty — good defensive coding even though GitHub names should
  be clean.
- **The MediaRemote legacy `dlopen` path is exemplary** — `dlopen` → `dlsym` →
  nil-return fail-closed. If the controller path matched it (C4), the bridge
  would be a model of safe private-API use.
- **`SystemDockController` captures prior autohide/delay/time-modifier** and
  restores them faithfully rather than clobbering user prefs.
- **`RunningAppsModel`'s bundle-id dedup** with the clear comment about why
  (magnification center-map desync) shows real understanding of downstream
  consequences.
- **CI basics are right**: `concurrency: cancel-in-progress` on PRs, pinned
  Xcode version, minimal `permissions:`.
- **Combine subscriptions consistently use `[weak self]`**; `LiveSystemStats`
  correctly centralizes what would otherwise be N independent timer storms; the
  32-bit counter wrap is *caught* (clamped to 0) rather than producing garbage.

---

*Reviewed against `main` @ `be22407`. Findings reference line numbers that are
current as of that commit; a few may drift as the file evolves — the file:line
citations should remain easy to relocate.*
