# GPT is awesome: Jetty review

Original review on 2026-06-28 against `main`. **All thirteen implement-now bugs
(BUG-1…BUG-13) have been fixed and merged to `main`** (one per `gpt/fix-*`
branch), so the bug list and its branch plan have been removed. What remains are
the larger items that want design or on-device validation, plus the delight ideas.

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

> Note: ISSUE-3 (the now-playing tile depending on a private MediaRemote bridge)
> is considered resolved — the tile ships **opt-in** (not in the first-run dock,
> added from Items ▸ Add ▸ Info Widget), the bridge is **isolated** under
> `Jetty/MediaRemote/` and **fails closed** (it `dlopen`s MediaRemote and returns
> nil when unavailable), and the privacy behavior is documented in `README.md`.

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
