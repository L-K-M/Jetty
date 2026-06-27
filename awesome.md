# awesome.md — a review of Jetty (and a pile of ideas)

## 🐞 Bugs & correctness

### BUG-4 — Per-display anchor *edge* is ignored by the dock content
The dock panel frame is computed from the per-display `anchor.edge`
(`DockPanelController`), but the SwiftUI content (`DockView`/`DockTileView`) reads
`preferences.edge`/`preferences.alignment` **directly** (`Dock/DockView.swift:18`,
`Dock/DockTileView.swift:122,164`). Today every panel shares the global anchor so it's
invisible, but the moment a per-display override sets a *different* edge than the global
default (the headline feature in MF-1), the window would be positioned/sized for one axis
while the tiles lay out for another. This is a latent landmine that **must** be fixed
before per-display positioning ships — `DockView` needs to consume the panel's anchor, not
the global preference. (Documented, not auto-fixed: best verified interactively alongside
MF-1.)

### BUG-5 — Off-edge reveal ergonomics for top/left/right docks
`DockPanelController.pointerInRevealZone` (`:153`) triggers against `screen.frame`, while
the hidden 2pt "peek" sits at `screen.visibleFrame` (`DockLayout.hiddenFrame`). For a
**top** dock the menu bar occupies the trigger band, and the peek lives *below* it — reveal
works only by shoving the pointer up into the menu bar. Bottom docks are fine (no reserved
strip). Worth a tuning pass: trigger against `visibleFrame` for non-bottom edges, and/or
widen the band.

### BUG-6 — `openCalendar()` hardcodes a bundle id and silently no-ops
`DockController.openCalendar` (`:305`) only tries `com.apple.iCal`; if Calendar is
missing/replaced the clock-tile click and "Open Calendar" menu item do nothing with no
feedback. Minor, but a `NSWorkspace.open(URL(string:"webcal://")…)`/default-handler
fallback would be more robust.

### BUG-7 — Panel reconcile thrash on every appearance tweak
`preferences.objectWillChange` → `applyPreferenceChange()`
(`Dock/DockController.swift:85`) runs `rebuildModel()` **and** `reconcilePanels()` on
*every* preference mutation — including each tick of the opacity/magnification/tint
sliders, none of which change panel geometry or the tile set. That recreates anchors and
re-lays-out (and can recreate) every panel dozens of times per drag. Appearance flows to
the view via `@ObservedObject` already; only structural prefs (edge/alignment/offset/inset/
iconSize/spacing/displayScope/showRunningApps/autoHide) need a relayout. Consider debouncing
or segmenting.

### BUG-8 — `DockModel` icon cache never invalidates / is unbounded
`DockModel.iconCache` (`Dock/DockModel.swift:28`) keys on tile id and never evicts or
refreshes. App icons that change after first cache (app update, theme) stay stale, and the
cache only grows. (Ironically, a perfectly good bounded LRU already exists in
`Common/LRUImageCache.swift` — currently **unused**; it was built for the later
window-preview feature.) A small TTL/▢-bounded cache would fix both.

### BUG-9 — No accessibility on dock tiles
`DockTileView` is a tap-gesture on a `Rectangle` with no `.accessibilityLabel`,
`.accessibilityAddTraits(.isButton)`, or value for the running state. For an app whose
entire job is to *replace the Dock*, VoiceOver users get an opaque grid. The running
indicator, clock, and Jetty-Menu tiles are likewise unlabeled.

### BUG-10 — Jetty Menu rebuilds app icons synchronously per row
`JettyMenuView.resultRow` (`Menu/JettyMenuView.swift:64`) calls
`NSWorkspace.shared.icon(forFile:)` on every row body evaluation with no caching, so fast
typing / scrolling re-fetches icons each frame. Cache by `item.id`.

---

## 🧱 General issues (robustness / UX / architecture)

### GI-1 — System-Dock "orphan" risk
The hide strategy sets `com.apple.dock autohide-delay = 1000`. If Jetty is force-quit,
crashes, or is **deleted** while managing, the real Dock stays effectively gone until the
user runs `defaults delete com.apple.dock autohide-delay; killall Dock` by hand. Mitigations
worth considering: re-assert with a *shorter* delay so a dead Jetty self-heals sooner;
document the one-line recovery in `README.md`; and/or a tiny login "watchdog". The
`Restore System Dock` button is great but only helps a *running* Jetty.

### GI-2 — `restoreSystemDock` drops the user's prior custom autohide-delay
`SystemDockController.restoreSystemDock` (`:62`) `removeObject`s `autohide-delay` /
`autohide-time-modifier` rather than restoring whatever the user had before. Someone who
ran a custom Dock auto-hide delay loses it. Capture & restore those alongside
`priorAutohide`.

### GI-3 — Hardcoded English strings everywhere
No `Localizable.strings` / `String(localized:)`. Fine for v0.1 but worth flagging before
any localization push; the clock already localizes correctly via `setLocalizedDateFormat…`,
which is a nice contrast.

### GI-4 — Magnification snaps per-tile instead of tracking the pointer
`DockView.scale(for:)` (`Dock/DockView.swift:70`) drives magnification off the **hovered
tile index** and integer tile distance, so the bump is identical anywhere within a tile and
jumps as you cross tile boundaries. The real Dock magnifies continuously along the exact
pointer position. `MagnificationCurve` is already continuous and ready; only the *input*
(pointer offset) is quantized. See ND-2.

### GI-5 — `RunningAppsModel` churn
Every workspace notification rebuilds the whole `apps` array and
`runningApplication(bundleIdentifier:)` re-scans `runningApplications` on each call
(`Apps/RunningAppsModel.swift:65`). During activate/deactivate storms this is avoidable
O(n) work; a dictionary index by bundle id would help.

---

## ✨ Missing features (advertised in PLAN/README but not yet wired)

### MF-1 — Per-display position UI (headline feature, no editor)
`DockDocument.anchorsByDisplayUUID`, `DockStore.setAnchor/clearAnchor`, and
`effectiveAnchor` all exist, and `README`/`PLAN §5,§520` sell "**per display**"
positioning as *the* differentiator over the real Dock — but **nothing in Settings ever
calls `setAnchor`**. `GeneralView` only edits the single global anchor; "Show on" just
toggles main-only vs all. This is the biggest promise-vs-reality gap. (Pairs with BUG-4.)

### MF-2 — Folder stacks (fan / grid / list)
`DockItemKind.folder` + `FolderStackStyle{fan,grid,list}` are modeled and
`DockItem.fromFileURL` even defaults a folder to `.grid` — but clicking a folder tile just
does `NSWorkspace.open(url)` (opens Finder). The advertised "stack" popover
(`PLAN §338,§353`) doesn't exist. A grid/list popover of the folder's contents would be a
big, visible win.

### MF-3 — Add web-link tiles from the UI ▶ implementing
`DockItem.fromLink(_:)` exists and `.url` tiles render/open fine, but the **Items ▸ Add**
menu (`Settings/ItemsView.swift:28`) has no "Link…" entry — there's no way to create one
without hand-editing `dock.json`. Add a small URL prompt.

### MF-4 — In-dock drag-to-reorder & drag-out-to-remove
`README` ("drag-to-pin and reorder") and `PLAN §357` ("Drag tiles | Reorder; drag out to
remove") promise reordering **in the dock itself**, but `DockTileView` only supports
`.onDrop`, tap, and context menu — no `.onDrag`. Reordering today is Settings-only.

### MF-5 — Recents in the Jetty Menu
`PLAN §128,§391,§521` describe the launcher as "app search, **recents**, and power
commands," but `JettyMenuModel` only ranks the static app index. A most-recently-launched
section (tracked from Jetty's own launches, no permissions needed) would make it far more
useful as a daily driver.

### MF-6 — Hotkeys are hardcoded, undiscoverable, and uncustomizable
`⌃⌥⌘D` (toggle) and `⌃⌥⌘Space` (menu) are registered in
`DockController.registerHotkeys` but never surfaced in Settings, and there's no way to
change or disable them. At minimum, show them in the Jetty Menu / General pane; ideally a
recorder. (`CarbonHotkey` already supports re-registration.)

### MF-7 — Rename / re-icon a pinned item
A pinned item's `displayName` is fixed at creation and there's no UI to edit it or set a
custom icon. The model (`DockItem.displayName`) supports it; the editor doesn't.

---

## 🎉 Novel / cool / delightful / quirky ideas

### ND-2 — Continuous, pointer-tracking magnification
Drive magnification from the live pointer x/y inside the dock (SwiftUI
`.onContinuousHover`, available on macOS 13+) instead of the hovered tile index, so tiles
swell fluidly as in the real Dock. `MagnificationCurve` is already continuous; this is
just feeding it a real offset. (See GI-4.) Delightful, medium-risk (feel needs tuning on
device).

### ND-3 — A family of info tiles (the clock proves the pattern)
The clock tile shows the architecture is ready for live widget tiles. Natural additions:
**battery %** (with a charging glow), **CPU/RAM meter**, **weather**, a **world clock**,
a **Pomodoro / countdown** tile, a "now playing" tile. Each is a small `…WidgetView` + a
`DockItemKind` case.

### ND-4 — Analog clock face option
A tiny rounded analog face (or a binary clock, for the nerds) as an alternate clock-tile
style — a 30-line `Canvas`/`TimelineView` flourish that makes the floating-island look
pop.

### ND-5 — The classic "poof" on remove
When an item is removed (drag-out or context menu), play the nostalgic Dock *poof* cloud +
fade. Pure delight, pure SwiftUI.

### ND-8 — Per-tile accent glow
On hover or while active, bloom a soft glow behind the tile in the icon's **dominant
color** (sampled once, cached). Cheap, gorgeous, very "Liquid Glass".

### ND-9 — Jetty Menu as a real command bar
Once the calculator (ND-1) lands, the same surface naturally grows **unit/currency
conversion**, **web-search fallback** ("press ⏎ to search the web for …"), and toggles
(Do Not Disturb, dark mode). The launcher becomes a tiny command palette.

---

## Decided to be out of scope - DO NOT IMPLEMENT

### ND-6 — ⌘1…⌘9 quick-launch
Launch the Nth pinned app with a chord, the way browsers switch tabs. Must stay
permission-free (Carbon hotkeys, not an event tap), so scope carefully — but it's a power-
user favorite.

### ND-7 — Shareable theme deep links & a gallery
Presets already import/export as JSON. Add a `jetty://theme/<base64>` URL so a look can be
shared in a single clickable link (and seed a small built-in gallery beyond the current 4).

### ND-10 — Auto-edge / "throw" the dock
Optional mode where the dock reveals at whichever edge you push the pointer to, or where
dragging the dock and "throwing" it snaps it to the nearest edge+alignment — turning
positioning into a gesture instead of four pickers.

--- 

## 🚀 What's being implemented now

Each ships on its own branch off `main` (kept to disjoint file sets to minimize merge
conflicts between the PRs):

| Branch | Entry | Footprint |
| --- | --- | --- |
| `claude/jetty-menu-calculator` | ND-1 | `Menu/ExpressionEvaluator.swift` (new), `Menu/JettyMenuModel.swift`, `Menu/JettyMenuView.swift`, new tests |
| `claude/jetty-menu-dismiss-on-blur` | BUG-2 | `Menu/JettyMenuController.swift` |
| `claude/dock-pin-bookmark-fixes` | BUG-3 | `Dock/DockController.swift` |
| `claude/items-add-link` | MF-3 | `Settings/ItemsView.swift` |
| `claude/dock-variable-tile-sizing` | BUG-1 | `Screens/DockLayout.swift`, `Dock/DockPanelController.swift`, new tests |

Everything else above is left as a triaged backlog. The high-value, higher-risk items
(MF-1 per-display UI + its BUG-4 prerequisite, MF-2 folder stacks, MF-4 in-dock reorder,
ND-2 continuous magnification) deserve an interactive, on-device session to get the feel
and multi-monitor behavior right, so they're documented rather than shipped blind.
</content>
</invoke>
