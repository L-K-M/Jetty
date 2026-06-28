# GPT is awesome: Jetty review

Original review on 2026-06-28 against `main`. The 13 implement-now bugs
(BUG-1…BUG-13) were fixed first. Subsequent passes then implemented **every**
design-level ISSUE:

- **ISSUE-1** — activate bundle-less running apps by PID.
- **ISSUE-2** — magnified end tiles no longer clip: the panel reserves
  magnification headroom along the dock axis as well as perpendicular.
- **ISSUE-3** — now-playing is opt-in / isolated / fail-closed.
- **ISSUE-4** — folder stacks load off the main thread, with drill-in.
- **ISSUE-5** — the live system widgets share one throttled sampler
  (`LiveSystemStats`, driven by the `DockController`) instead of each
  `TimelineView` tile polling per display.
- **ISSUE-6** — the app index refreshes on menu open and scans one level deeper.
- **ISSUE-7** — a stale bookmark refreshed at launch is written back to
  `DockStore` (opening routes through `DockStore.resolvedURL(forItemID:)`), so
  moved files/apps keep working on later launches.
- **ISSUE-8** — tolerant/lossy document decoding (one bad item/anchor no longer
  loses the dock).
- **ISSUE-9** — a corrupt primary can no longer overwrite the good `.bak`.

The bugs and all ISSUEs are done. What remains are the optional, delight-level
ideas below.

## Delightful improvement ideas (backlog)

Nice-to-haves, not defects — a menu of future polish.

### IDEA-1 — Edge reveal heat map

Show a tiny, optional glow in the reveal band after failed edge attempts. It
would teach users where the dock lives without leaving a permanent sliver.

### IDEA-2 — Per-display personalities

Let each display have a subtle independent accent/preset: work monitor gets a
sober command strip, laptop display gets playful glass and widgets. (Larger:
needs per-display appearance overrides in the store + settings UI.)

### IDEA-3 — Dock “breathing” on wake

After wake or display reconnect, briefly pulse the Jetty dock once to
communicate that it reclaimed the system Dock state and restored placement.

### IDEA-4 — Stack previews as spatial memory

Folder stacks could remember their last hovered item and lightly bias focus
there next time, useful for Downloads/Desktop workflows.

### IDEA-5 — Trash mood (partly shipped)

The Trash tile now reflects empty vs. full live (watched via `TrashMonitor`).
Remaining: a brief “hot” state right after a drop, and a satisfying poof when
the Trash is emptied.
