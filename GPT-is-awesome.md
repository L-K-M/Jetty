# GPT is awesome: Jetty review

Original review on 2026-06-28 against `main`. The 13 implement-now bugs
(BUG-1…BUG-13) were fixed and merged earlier. Since then a second pass implemented
several of the design-level items below: **ISSUE-1** (activate bundle-less running
apps by PID), **ISSUE-3** (now-playing is opt-in / isolated / fail-closed),
**ISSUE-4** (folder stacks now load off the main thread, with drill-in), **ISSUE-6**
(the app index refreshes on menu open and scans one level deeper), **ISSUE-8**
(tolerant/lossy document decoding — one bad item/anchor no longer loses the dock),
and **ISSUE-9** (a corrupt primary can no longer overwrite the good `.bak`). Those
are removed from the list. What remains are the items still worth doing.

## Good ideas that need more care

### ISSUE-2 — Magnified first/last tiles can still clip along the dock axis

- Severity: Medium
- Area: `Jetty/Dock/DockPanelController.swift`, `contentSize()`
- Problem: magnification headroom is added only perpendicular to the dock. `scaleEffect` grows in both dimensions, so end tiles can clip at the window's along-axis edges.
- Suggested direction: add along-axis headroom or constrain magnification to grow inward/perpendicular. Needs visual tuning so it does not create dead reveal areas.

### ISSUE-5 — Live system widgets duplicate polling work per display

- Severity: Low/Medium
- Area: `Jetty/Widgets/SystemMonitorWidgetView.swift`, `Jetty/Widgets/BatteryWidgetView.swift`
- Problem: each tile instance polls independently via `TimelineView`. Multiple displays mean duplicated sampling even while panels are hidden.
- Suggested direction: centralize sampled stats in a shared throttled service and reduce cadence while hidden.

### ISSUE-7 — Bookmark stale refresh is detected but not persisted

- Severity: Medium
- Area: `Jetty/Store/BookmarkResolver.swift`, `Jetty/Apps/AppLauncher.swift`
- Problem: stale security/bookmark data can be refreshed, but the updated bookmark is not written back to `DockStore`.
- Impact: moved apps/files may work once and then fail later because stale bookmark data remains in `dock.json`.
- Suggested direction: route resolution through a store-aware helper that updates the corresponding item after stale resolution.

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
