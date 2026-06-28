# GPT is awesome: Jetty review

Reviewed on 2026-06-28 against `main`. The earlier `awesome.md` backlog has already landed a lot of good work, so this list focuses on issues still visible in the current tree.

## Implement-now candidates

These are small, high-confidence fixes that should be safe to branch independently.

### BUG-1 — Edge reveal can fire after the pointer already left

- Severity: High
- Area: `Jetty/Dock/DockPanelController.swift`, `handleMouseMoved(to:)` / `scheduleReveal()`
- Problem: entering the reveal band schedules a delayed reveal, but leaving the band before `revealDelayMs` does not cancel `revealWork`. The dock can pop open after the user merely brushed the screen edge.
- Impact: surprising reveals, especially with longer delays and side/top docks.
- Fix: when hidden and the pointer is still on the same screen but no longer in `pointerInRevealZone`, cancel and clear `revealWork`. Also cancel it when the pointer leaves the screen.
- Implementation confidence: High.

### BUG-2 — Per-display anchor edits do not refresh existing panels

- Severity: High
- Area: `Jetty/Dock/DockController.swift`, `store.objectWillChange` observation
- Problem: document changes rebuild the tile model and call `relayoutPanels()`, but an existing `DockPanelController` receives a new anchor only from `reconcilePanels()`. A Settings change to `anchorsByDisplayUUID` can leave a panel on its old edge/alignment until some unrelated reconciliation happens.
- Impact: the headline per-display placement feature can look broken or stale.
- Fix: on store document changes, call `rebuildModel()` and `reconcilePanels()`. This is a little more work for item-only edits, but document writes are user-driven and correctness matters more.
- Implementation confidence: High.

### BUG-3 — Toggle hotkey cannot hide an always-visible dock

- Severity: Medium
- Area: `Jetty/Dock/DockPanelController.swift`, `toggle()` / `hide()`
- Problem: `hide()` refuses to do anything when `preferences.autoHide == false`, so the toggle hotkey can reveal an always-visible/manual dock but cannot hide it again.
- Impact: the advertised toggle behaves one-way in non-auto-hide mode.
- Fix: add an explicit hide path used by `toggle()` that does not respect the auto-hide guard, while keeping ordinary pointer/launch hides guarded.
- Implementation confidence: High.

### BUG-4 — Empty Trash from the dock skips confirmation

- Severity: High
- Area: `Jetty/Dock/DockController.swift`, trash context menu
- Problem: the Jetty Menu asks for confirmation before destructive power commands, but the dock trash context menu calls `PowerCommandRunner.run(.emptyTrash)` directly.
- Impact: one accidental context-menu click can permanently empty Trash.
- Fix: show an `NSAlert` before running `.emptyTrash`, reusing wording similar to the Jetty Menu confirmation.
- Implementation confidence: High.

### BUG-5 — Jetty Menu advertises Return for commands but Return launches apps/searches instead

- Severity: Medium
- Area: `Jetty/Menu/JettyMenuModel.swift`, `activateSelection()`
- Problem: `JettyMenuView.commandRow` says `return run`, but `activateSelection()` always prioritizes the selected app result before `model.command`.
- Impact: quick toggles feel broken from the keyboard.
- Fix: if `command` is non-nil, run `onRunCommand` before falling back to app launch or web search.
- Implementation confidence: High.

### BUG-6 — Search URL encoding can leak query separators

- Severity: Low/Medium
- Area: `Jetty/Menu/JettyMenuController.swift`, `webSearch(_:)`
- Problem: `addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)` can leave characters such as `&` meaningful inside the query string.
- Impact: searching for `a&b` can be interpreted as multiple parameters instead of literal text.
- Fix: construct the URL with `URLComponents` and a `URLQueryItem`.
- Implementation confidence: High.

### BUG-7 — System Dock defaults are restarted before being explicitly synchronized

- Severity: Medium
- Area: `Jetty/SystemDock/SystemDockController.swift`
- Problem: writes to `UserDefaults(suiteName: "com.apple.dock")` are followed immediately by `killall Dock`. If the preference daemon has not flushed yet, Dock can relaunch with stale values.
- Impact: hide/restore/reassert can be flaky, exactly in the area users most need to trust.
- Fix: synchronize the Dock defaults before `restartDock()`, ideally in one helper that sets/removes and flushes.
- Implementation confidence: High.

### BUG-8 — Reassert ignores `autohide-time-modifier` drift

- Severity: Low/Medium
- Area: `Jetty/SystemDock/SystemDockController.swift`, `reassertIfManaging()`
- Problem: reassert checks `autohide` and `autohide-delay` but not `autohide-time-modifier`.
- Impact: if Tahoe or another utility changes only the time modifier, Jetty may leave the system Dock animation/reveal timing in an inconsistent state.
- Fix: include `autohide-time-modifier` in the drift check.
- Implementation confidence: High.

### BUG-9 — Drag-and-drop URL collection mutates shared state from provider callbacks

- Severity: Low/Medium
- Area: `Jetty/Dock/DockTileView.swift`, `loadURLs(from:)`
- Problem: `NSItemProvider.loadObject` callbacks may arrive concurrently. Appending to the same local `urls` array is not thread-safe.
- Impact: rare crashes, lost URLs, or corrupted drop ordering during multi-file drops.
- Fix: append on a serial queue or dispatch each append to the main queue before the final callback.
- Implementation confidence: High.

### BUG-10 — Weather can show stale data after location/unit changes

- Severity: Medium
- Area: `Jetty/Widgets/WeatherWidgetView.swift`, `Jetty/Widgets/WeatherService.swift`
- Problem: the view displays `service.snapshot` without verifying that it matches the current latitude/longitude/unit. If coordinates change and the new request is pending or fails, the tile can show old data for the wrong place or unit.
- Impact: misleading weather tile.
- Fix: carry a request key in `WeatherSnapshot` or expose the service key, clear mismatched snapshots on key change, and only display matching data.
- Implementation confidence: High.

### BUG-11 — Pomodoro countdown drifts during sleep, stalls, and event-tracking modes

- Severity: Medium
- Area: `Jetty/Widgets/PomodoroTimer.swift`
- Problem: the timer decrements by one each scheduled tick. `Timer.scheduledTimer` can pause during sleep, modal loops, and tracking run-loop modes, so elapsed wall-clock time is not represented.
- Impact: the tile can overstate remaining time after sleep or UI stalls.
- Fix: store an end `Date`, compute remaining from wall-clock time on each refresh, and add the timer to `.common`.
- Implementation confidence: High.

### BUG-12 — Update downloads trust the GitHub asset filename too much

- Severity: Medium
- Area: `Jetty/Updates/UpdateDownloader.swift`
- Problem: `asset.name` is used directly as a Downloads child path. Path separators, control characters, hidden-ish names, or odd Unicode can produce surprising names or failed moves.
- Impact: confusing downloads and avoidable filesystem edge cases.
- Fix: sanitize to a filename, reject path separators/control characters, and fall back to a safe basename while preserving normal extensions.
- Implementation confidence: High.

### BUG-13 — Prerelease version ordering is lexicographic, not SemVer

- Severity: Medium
- Area: `Jetty/Updates/SemanticVersion.swift`
- Problem: `beta.10` compares older than `beta.2` lexicographically, contrary to SemVer numeric identifier rules.
- Impact: prerelease update checks can suggest downgrades or skip real updates.
- Fix: split prerelease identifiers on `.`, compare numeric identifiers numerically, numeric identifiers lower than nonnumeric, and shorter equal-prefix prereleases lower.
- Implementation confidence: High.

## Good ideas that need more care

These look worthwhile, but I would not ship them blind without more design or on-device validation.

### ISSUE-1 — Running apps without bundle identifiers become dead tiles

- Severity: Medium
- Area: `Jetty/Dock/DockModel.swift`, `Jetty/Dock/DockController.swift`
- Problem: running-only tiles can be keyed by PID-like `RunningAppInfo.id`, but `openApplication(_:)` only activates by bundle identifier or app URL.
- Impact: bundle-less apps can appear in the dock but not activate when clicked.
- Suggested direction: carry `processIdentifier` through `RunningAppInfo` and `DockTile`, then activate by PID as a fallback.

### ISSUE-2 — Magnified first/last tiles can still clip along the dock axis

- Severity: Medium
- Area: `Jetty/Dock/DockPanelController.swift`, `contentSize()`
- Problem: magnification headroom is added only perpendicular to the dock. `scaleEffect` grows in both dimensions, so end tiles can clip at the window's along-axis edges.
- Suggested direction: add along-axis headroom or constrain magnification to grow inward/perpendicular. Needs visual tuning so it does not create dead reveal areas.

### ISSUE-3 — Now Playing uses a private MediaRemote bridge in a core-looking widget

- Severity: High
- Area: `Jetty/Widgets/NowPlayingService.swift`
- Problem: the now-playing tile appears to depend on a private MediaRemote bridge. The project guidance allows private APIs only isolated for later features, and listening metadata is privacy-sensitive.
- Suggested direction: make the widget explicitly opt-in, document the privacy behavior, weak-link/fail closed, and keep it out of first-run defaults.

### ISSUE-4 — Folder stack opening can hitch the dock

- Severity: Medium
- Area: `Jetty/Stacks/FolderStackController.swift`, `Jetty/Stacks/FolderStack.swift`
- Problem: opening a stack synchronously enumerates folder contents and loads icons on the main thread.
- Impact: large, network, or cloud-backed folders can stutter the dock.
- Suggested direction: show the panel immediately with a loading state, enumerate off-main, and cache icons.

### ISSUE-5 — Live system widgets duplicate polling work per display

- Severity: Low/Medium
- Area: `Jetty/Widgets/SystemMonitorWidgetView.swift`, `Jetty/Widgets/BatteryWidgetView.swift`
- Problem: each tile instance polls independently via `TimelineView`. Multiple displays mean duplicated sampling even while panels are hidden.
- Suggested direction: centralize sampled stats in a shared throttled service and reduce cadence while hidden.

### ISSUE-6 — App index misses nested apps and does not refresh when apps are installed

- Severity: Low/Medium
- Area: `Jetty/Menu/AppIndex.swift`
- Problem: the launcher scans a limited set of app directories and does not appear to observe install/uninstall changes.
- Impact: apps in subfolders or newly installed apps may be missing until restart.
- Suggested direction: shallow recursive scan plus FSEvents/metadata refresh on menu open.

### ISSUE-7 — Bookmark stale refresh is detected but not persisted

- Severity: Medium
- Area: `Jetty/Store/BookmarkResolver.swift`, `Jetty/Apps/AppLauncher.swift`
- Problem: stale security/bookmark data can be refreshed, but the updated bookmark is not written back to `DockStore`.
- Impact: moved apps/files may work once and then fail later because stale bookmark data remains in `dock.json`.
- Suggested direction: route resolution through a store-aware helper that updates the corresponding item after stale resolution.

### ISSUE-8 — Forward compatibility for unknown enum raw values is fragile

- Severity: High
- Area: `Jetty/Model/DockDocument.swift`, `DockItem.swift`, `DockAnchor.swift`, `AppearancePreset.swift`
- Problem: unknown enum raw values can fail document decoding. Unknown keys are fine, but unknown future enum cases are not.
- Impact: a future build, hand-edited JSON, or a partially corrupt item can make Jetty fall back to backup/defaults and look like it lost the dock.
- Suggested direction: tolerant enum decoding or lossy item/anchor decoding, with tests for unknown raw values.

### ISSUE-9 — Backup preservation can overwrite the last good backup after fallback loading

- Severity: High
- Area: `Jetty/Store/DockStore.swift`, `saveNow()` / `load(from:)`
- Problem: `saveNow()` copies the current primary to `.bak` before writing. If the primary was corrupt and the app loaded from `.bak`, the next save can replace the good backup with the corrupt primary.
- Impact: the recovery file can be destroyed during recovery.
- Suggested direction: track whether the primary decoded successfully, restore backup to primary on fallback, or only back up known-good primary files.

## Delightful improvement ideas

### IDEA-1 — Edge reveal heat map

Show a tiny, optional glow in the reveal band after failed edge attempts. It would teach users where the dock lives without leaving a permanent sliver.

### IDEA-2 — Per-display personalities

Let each display have a subtle independent accent/preset: work monitor gets a sober command strip, laptop display gets playful glass and widgets.

### IDEA-3 — Dock “breathing” on wake

After wake or display reconnect, briefly pulse the Jetty dock once to communicate that it reclaimed the system Dock state and restored placement.

### IDEA-4 — Stack previews as spatial memory

Folder stacks could remember their last hovered item and lightly bias focus there next time, useful for Downloads/Desktop workflows.

### IDEA-5 — Trash mood

The Trash tile could subtly change expression/state: empty, full, “hot” after a recent drop, and a satisfying poof when emptied.

## Suggested branch plan

- `gpt/fix-reveal-cancel`: BUG-1.
- `gpt/fix-menu-command-return`: BUG-5.
- `gpt/fix-web-search-url`: BUG-6.
- `gpt/fix-system-dock-sync`: BUG-7 and BUG-8.
- `gpt/fix-drop-url-race`: BUG-9.
- `gpt/fix-weather-stale-snapshot`: BUG-10.
- `gpt/fix-pomodoro-wall-clock`: BUG-11.
- `gpt/fix-update-download-filenames`: BUG-12.
- `gpt/fix-semver-prerelease`: BUG-13.

BUG-2, BUG-3, and BUG-4 are good fixes too, but all touch `DockController.swift` or overlap the same dock-control region as other work. They should be handled deliberately if these local branches are turned into PRs, or batched into one dock-controller PR to avoid needless conflicts.
