# Jetty — A Modern, Native Dock for macOS Tahoe

A fast, beautiful, **auto-hiding dock** for macOS 26 (Tahoe) that stands in for the
system Dock — with the things the real Dock still won't give you: **free positioning**
(bottom-right, top-left, a floating island anywhere along an edge), **deep visual
control** (native Liquid Glass, tint, size, spacing, indicator style — with shareable
presets), and **built-in extras** (a live **date/time** tile and a Windows-Start-style
**Jetty Menu** with instant app search and power commands).

> **Lineage & siblings.** Jetty is the third app in the same family as
> **[Zap](../Zap)** (a ⌘-Tab switcher replacement) and **[MacDring](../MacDring)** (a
> DragThing-style edge-tab launcher). It reuses their house style wholesale: a Swift
> menu-bar agent, SwiftUI content over AppKit windowing, `UserDefaults`-backed
> `Preferences`, a GitHub self-updater, Carbon hotkeys, and the shared
> `lkm-build`/`lkm-release` tooling. Where Zap owns *switching* and MacDring owns
> *launching from edges*, Jetty owns *the dock itself*.

---

## 0. Feasibility — Can this be built? (the first question)

**Verdict: feasible, and de-risked by one design decision.** A polished, reliable,
*notarizable* dock that takes over from the system Dock is shippable today on macOS
Tahoe using **only public APIs** — this is proven by **uBar**, **ActiveDock 2**, and the
open-source **DockDoor**, all of which run on macOS 26. The catch every honest plan must
state up front:

> **You cannot truly *replace* the macOS Dock — you can only *hide* it and run
> *alongside* it.** The Dock is a SIP-protected, launchd-managed system process that also
> hosts Mission Control, Spaces transitions, and the minimize/genie animation. There is
> **no public (or even unprivileged private) API to disable or remove it**, and injecting
> into `Dock.app` (the cDock / yabai route) requires disabling SIP — a non-starter for a
> distributable consumer app. So Jetty is a **co-resident** dock: it hides the real Dock
> and draws its own.

### What makes Jetty *easier* than a generic "dock replacement"

Two product decisions cut away the hardest and riskiest parts of the category:

1. **No screen-space reservation.** The single *confirmed blocker* for dock replacements
   is that **no public API lets a third-party app shrink `NSScreen.visibleFrame`** to
   reserve an edge strip (Apple's own feature request, FB9985546, has sat unimplemented
   since 2022 and remains open on Tahoe). uBar/DockDoor work around it by *nudging other
   apps' windows* with the Accessibility API — a fragile hack that silently fails for
   non-AppKit apps (Java, Carbon/Photoshop, some Electron). **Jetty opts out entirely:**
   it is **hidden by default and floats *over* whatever is on screen when revealed.** No
   reservation, no window-nudging, **no Accessibility permission required for the core
   dock.** This is the user-chosen model and it removes the category's worst correctness
   gap.

2. **Auto-hidden overlay.** Because Jetty is hidden until you summon it (pointer to the
   screen edge, or a hotkey), it never has to "own" persistent screen real estate or
   fight maximized windows. It's the exact borderless, non-activating `NSPanel` pattern
   Zap already ships for its switcher overlay — just pinned to a screen edge.

### The feasibility ledger (verified against current sources)

| Capability | Verdict | API surface | Permission |
|---|---|---|---|
| Hide the real Dock | ✅ works (fragile on Tahoe) | `defaults write com.apple.dock autohide -bool true` + `autohide-delay 1000` + `killall Dock` once | none |
| Draw an edge overlay across Spaces / over fullscreen | ✅ | borderless `NSPanel`, high window level, `collectionBehavior` all-spaces + `fullScreenAuxiliary` | none |
| List/launch/activate/hide/quit apps + running indicators | ✅ public, robust | `NSWorkspace.runningApplications`, `NSRunningApplication`, workspace notifications | **none** |
| App icons | ✅ | `NSWorkspace.icon(forFile:)`, `NSRunningApplication.icon` | none |
| Drag a file onto an app to open-with | ✅ | `NSDraggingDestination` + `NSWorkspace.open(_:withApplicationAt:)` | none |
| Native Liquid Glass look | ✅ public (macOS 26 only) | `NSGlassEffectView`/`NSGlassEffectContainerView`, SwiftUI `.glassEffect` | none |
| Reveal-on-edge-hover / global hotkey | ✅ | global **mouse** monitor; Carbon `RegisterEventHotKey` | none |
| Date/time tile, Trash, folder stacks, separators | ✅ | `DateFormatter`, `FileManager`, `NSWorkspace` | none |
| Jetty Menu: app search | ✅ | scan `/Applications` + `NSMetadataQuery` (Spotlight) | none |
| Jetty Menu: power commands (sleep/restart/shut down/log out) | ✅ | AppleEvents to `loginwindow`/System Events (or `osascript`) | Automation (per-target, first use) |
| Per-app window list, click-to-raise, minimize/restore | ✅ | `CGWindowList` enumeration + Accessibility `AXUIElement` (private `_AXUIElementGetWindow` resolved via `dlsym`); raise degrades to app-activate without AX | **Accessibility** (optional) |
| Live hover **window previews** | ✅ | **ScreenCaptureKit** thumbnails (`SCScreenshotManager`, macOS 14+; glyph fallback on 13); list + raise/minimize still work without it | **Screen Recording** (optional) |
| Mirror another app's unread **badge** | ⚠️ best-effort, later | undocumented AX `AXStatusLabel` on the Dock process (polling) or `lsappinfo StatusLabel` | Accessibility |
| Reserve screen space (windows respect the dock) | ❌ not cleanly possible | (would need private SkyLight + SIP off) | — |
| True minimize-to-this-dock genie / Stage-Manager parity | ❌ Dock-exclusive | — | — |

**Bottom line:** everything in Jetty's **v1** (the columns marked ✅, which include all
three of the user's headline asks — positioning, visual styles, date/time + Start menu)
is achievable with **public APIs and no scary permissions**. The ⚠️ window-management
features are real, proven (DockDoor does them), and slotted for **later milestones** as
*opt-in* additions behind their permissions. The ❌ rows are honest non-goals dictated by
the platform, not by effort.

### Distribution is solved, App Store is not

Jetty is a **Developer ID-signed, notarized, hardened-runtime, non-sandboxed** menu-bar
agent (`LSUIElement`) — exactly like uBar, ActiveDock, DockDoor, Zap, and MacDring. The
**App Store is out of scope**: the sandbox makes `AXIsProcessTrusted()` return false, so a
sandboxed build could never offer the later window-management features. Importantly,
**using a private symbol does *not* block notarization** — Apple's notary service is a
malware/signature scan, not App Review (confirmed by Apple DTS). Private APIs are a
*maintenance* risk, not a *distribution* one, so the few we may ever touch
(`_AXUIElementGetWindow`, `AXStatusLabel`) are weak-imported and isolated behind
fallbacks.

### Tahoe-specific caveats we design around (verified)

- **The auto-hide trick is "usually works," not "guaranteed."** macOS 26.0–26.0.1 had a
  Dock auto-hide regression (the Dock vanishing or sticking), partly fixed in 26.1. Jetty
  therefore **re-asserts** the defaults on launch / wake / display change and ships a
  one-click **Restore system Dock**.
- **`killall Dock` does *not* break ⌘-Tab** (handled at the loginwindow level) but does
  briefly interrupt Mission Control / minimize while the Dock respawns — so Jetty calls it
  **exactly once** to apply the setting, never as an ongoing strategy.
- **Liquid Glass renders only on macOS 26 and needs Xcode 26.** Jetty branches
  `@available(macOS 26, *)` to `NSGlassEffectView` and falls back to `NSVisualEffectView`
  on macOS 14–15, and honors **Reduce Transparency** / **Tinted** appearance settings.
- **Screen Recording** (for the *later* preview feature) re-prompts periodically on
  Sequoia/Tahoe and shows the recording indicator, and Tahoe requires a real signed
  `.app` bundle — which is why previews are **opt-in** and the dock is fully usable
  without them.

---

## 1. Goals & Non-Goals

### Goals (v1)
- **Be the dock you actually look at.** Hide the system Dock and present a fast, native,
  auto-hiding dock of pinned + running apps with live running indicators, one-click
  launch/activate, drag-to-open, and a synthesized right-click menu.
- **Position it anywhere.** Any **edge** (bottom/top/left/right) × any **alignment**
  (leading / center / trailing) × a fine **offset**, **per display**. "Bottom-right" is a
  two-click setting, not a fantasy.
- **Look exactly how you want.** Native **Liquid Glass** (regular/clear/tinted) or
  solid/gradient; tunable icon size, tile spacing, corner radius, indicator style,
  background opacity, optional **magnification** — all live-previewed and saved as
  **shareable presets** (JSON import/export, à la Zap themes).
- **Do more than the Dock.** A live **date/time tile** and the **Jetty Menu** — a
  Start-menu-style panel with instant **app search**, recents, and **power commands**
  (Sleep / Restart / Shut Down / Log Out / Lock / Empty Trash).
- **Trustworthy & light.** Menu-bar agent, no Dock icon of its own, **no permissions for
  the core dock**, no heavy dependencies, instant reveal, clean uninstall that restores
  the real Dock.
- **Multi-monitor & restart-stable.** Each display can carry its own dock placement;
  positions are keyed by a **stable display UUID** so they survive reboot, resolution
  change, and reconnection (MacDring's proven model).

### Non-Goals (v1)
- **Truly replacing / disabling the system Dock**, or owning its system duties (Mission
  Control, Spaces, the genie minimize). Jetty hides it and coexists.
- **Reserving screen space** so other windows avoid the dock. By design Jetty floats over
  content and auto-hides; it does **not** nudge other apps' windows (no Accessibility
  dependency in v1).
- **Window peeking / live previews** — **shipped**: hovering a running app's tile shows a
  popover of its windows, anchored to the icon. A `WindowPreviewMode` setting picks
  **Off**, **Window names** (the default — needs no Screen Recording; titles via
  Accessibility, else "Window N"), or **Live thumbnails** (ScreenCaptureKit). Click to
  raise / minimize via Accessibility, degrading to app-activate without it. See
  `Jetty/Windows/`. **Alt-tab / badge mirroring** are still later.
- **SIP-disabling or `Dock.app` injection** (cDock/Docky route). Permanently off-limits.
- **App Store distribution.** Developer ID + notarization only.
- **Stage Manager / native-fullscreen parity.** Jetty stays out of the way there (auto-hide
  / hover-reveal), best-effort.

---

## 2. Design Principles

1. **Hide, never fight.** Jetty is an overlay that appears on demand and floats above
   everything; it never reserves space, never moves your windows, never steals focus
   (non-activating panel). Overlap-on-reveal is a feature, not a compromise.
2. **No-permission core.** The whole v1 dock runs on `NSWorkspace` + windowing + a global
   *mouse* monitor — zero TCC prompts. Permissions appear only when a user opts into a
   *later* power feature, and the dock degrades gracefully without them.
3. **Native by adoption, not imitation.** Match Tahoe by using the *real* Liquid Glass
   APIs and honoring the user's transparency/tint settings — don't fake glass with a blur.
4. **Positions are muscle memory.** Placement is sacred and restored exactly, keyed to a
   durable display identity and a fractional/aligned anchor — never raw pixels.
5. **Borrow the family house style.** Same project shape, conventions, updater, and CI as
   Zap and MacDring (§11) so the three apps stay a coherent suite.
6. **Honest about the platform.** Where macOS won't cooperate (space reservation, Dock
   internals, fragile defaults), say so in-product and design for graceful failure +
   one-click restore.

---

## 3. High-Level Architecture

A background **menu-bar agent** (`LSUIElement = true`, `.accessory` policy). It hides the
system Dock, owns one auto-hiding **dock panel per active display**, and drives them from
a central controller fed by a persisted document, live app state, and global prefs.

```
┌────────────────────────────────────────────────────────────────────────────┐
│ Jetty (LSUIElement agent app)                                                │
│                                                                              │
│  ┌──────────────┐   ┌────────────────────┐   ┌───────────────────────────┐  │
│  │ DockStore    │   │ DisplayRegistry    │   │ RunningAppsModel          │  │
│  │ Codable JSON │   │ NSScreen ⇄ UUID    │   │ NSWorkspace running apps  │  │
│  │ pinned items │   │ screen-change obs.  │   │ + launch/quit/activate    │  │
│  └──────┬───────┘   └─────────┬──────────┘   └────────────┬──────────────┘  │
│         │ items               │ screens                    │ live app set    │
│         ▼                     ▼                            ▼                 │
│  ┌────────────────────────────────────────────────────────────────────────┐│
│  │ DockController (the brain)                                              ││
│  │  - merges pinned + running → ordered tiles (DockModel)                  ││
│  │  - resolves each display's anchor → panel frame (DockLayout)            ││
│  │  - drives auto-hide / edge-hover reveal / hotkey toggle                 ││
│  │  - launch/activate, drag-to-open, right-click menu, Jetty Menu          ││
│  └───────┬───────────────────────────────────────────────┬────────────────┘│
│          │ one per display                                 │ shared          │
│          ▼                                                 ▼                 │
│  ┌────────────────────────┐                    ┌──────────────────────────┐ │
│  │ DockPanel (NSPanel,     │  reveal/hide       │ JettyMenuPanel (NSPanel) │ │
│  │ borderless, non-        │ ◀───────────────▶  │ search + recents + power │ │
│  │ activating, all-Spaces) │                    └──────────────────────────┘ │
│  │  SwiftUI DockView:      │                                                  │
│  │  GlassEffectContainer   │   ┌────────────────┐  ┌─────────────────────┐   │
│  │  of tiles + ClockWidget │   │ SystemDock     │  │ AppLauncher         │   │
│  │  + Trash + JettyMenu btn│   │ Controller     │  │ NSWorkspace open/   │   │
│  └────────────────────────┘   │ hide/restore   │  │ activate/openWith   │   │
│                                │ real Dock      │  └─────────────────────┘   │
│  ┌────────────────┐  ┌───────────────────────┐ └────────────────┘           │
│  │ StatusItem     │  │ Settings (SwiftUI)    │  ┌────────────────────────┐   │
│  │ (menu bar)     │  │ General/Appearance/   │  │ Preferences            │   │
│  │ Settings, Quit │  │ Items/Menu/Perms/About│  │ (UserDefaults)         │   │
│  └────────────────┘  └───────────────────────┘  └────────────────────────┘   │
│  ┌────────────────┐  ┌───────────────────────┐  ┌────────────────────────┐   │
│  │ CarbonHotkey   │  │ UpdateChecker (GitHub)│  │ PowerCommands (AppleEv.)│  │
│  └────────────────┘  └───────────────────────┘  └────────────────────────┘   │
└────────────────────────────────────────────────────────────────────────────┘
```

**Tech stack:** Swift 5; SwiftUI for the dock/menu/Settings content; AppKit for
windowing (`NSPanel`, `NSStatusItem`, `NSVisualEffectView`, `NSGlassEffectView` on macOS
26); `NSWorkspace`/`NSRunningApplication` for apps; Carbon `RegisterEventHotKey` for the
optional toggle hotkey; AppleEvents/`NSAppleScript` for power commands; `SMAppService` for
launch-at-login. Document persisted as Codable JSON in Application Support; global prefs in
`UserDefaults`. **Builds with Xcode 26; deployment target macOS 13** (Liquid Glass gated
to 26, with a fallback below).

---

## 4. The auto-hidden overlay model (core decision)

Jetty's dock is a **borderless, non-activating `NSPanel`** — the same windowing recipe
proven in Zap's `OverlayWindowController`:

```swift
window.isOpaque = false
window.backgroundColor = .clear
window.hasShadow = true
window.level = .popUpMenu                 // floats above ordinary + most utility windows
window.isReleasedWhenClosed = false
window.isRestorable = false
window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
// styleMask includes .nonactivatingPanel so clicking the dock never steals focus
```

- **Hidden by default.** The panel is **parked on-screen** at its revealed frame at all
  times, with its content slid off-edge (and made click-through) while hidden — it is
  never moved off-screen. It is **revealed** when: (a) the pointer reaches the dock's
  screen edge (a global **mouse** monitor — no permission), held for a short, configurable
  delay; or (b) the user presses the optional global **toggle hotkey** (Carbon — no
  permission). It **hides** on pointer-leave (with a grace delay), after launching an item
  (configurable), or on `Esc`.
- **Overlaps, never reserves.** On reveal the content slides in *over* whatever is there.
  No window is moved. This is the explicit product choice that removes the Accessibility
  dependency and the non-AX-app failure mode.
- **Reveal/hide animation = content-layer slide, not a window move.** The panel stays
  parked at the revealed frame; reveal/hide animates only a content sublayer's
  `CATransform3D` translation along the perpendicular axis (fully off its edge when
  hidden, clipped by the layer-backed container). This is pure GPU compositing of an
  already-rendered, never-discarded backing — animating the *window frame* from off-screen
  instead discarded the backing and forced a full SwiftUI re-render mid-slide, which was
  the source of reveal stutter and the "stuck half-revealed" hitch. *Reduce Motion* →
  instant. The panel is click-through (`ignoresMouseEvents`) while hidden so the
  transparent parked window never intercepts events; the global edge-hover monitor still
  triggers reveal.
- **Always-available "peek" option.** A setting keeps a thin always-visible sliver (or a
  fully pinned, always-shown dock) for users who don't want auto-hide — same
  `DockLayout` math, just a different resting frame.
- **Robustness lessons inherited from Zap:** recycle the borderless window if it ages out
  after long compositor uptime; defer first reveal until the SwiftUI host reports a real
  `fittingSize` (avoid the "small square" glitch); `acceptsFirstMouse` so the first click
  on the inactive panel registers.

Over a **native-fullscreen** Space or when **Stage Manager** is active, Jetty stays
hidden and only hover/hotkey-reveals (overlay there is possible but documented as
best-effort) — it never tries to reserve or rearrange.

---

## 5. Positioning — better than the Dock (improvement #1)

The real Dock gives you three positions (bottom/left/right) and always centered. Jetty
generalizes this into a small, pure, unit-tested geometry layer (`DockLayout`), reusing
MacDring's `ScreenAnchor` idea (stable display UUID + fractional placement):

```swift
enum DockEdge: String, Codable { case bottom, top, left, right }
enum DockAlignment: String, Codable { case leading, center, trailing }

struct DockAnchor: Codable, Equatable {
    var displayUUID: String     // CGDisplayCreateUUIDFromDisplayID — stable across reboots
    var edge: DockEdge          // which screen edge the dock hugs
    var alignment: DockAlignment// where along that edge it sits
    var offset: Double          // fine nudge in points from the aligned position (± )
    var inset: Double           // gap from the very edge (a "floating island" look)
}
```

`DockLayout` (pure, no AppKit beyond `CGGeometry`) turns an anchor + the panel's measured
content size + the target screen's `visibleFrame` into the on-screen frame, for both the
**revealed** and **hidden** states (off-edge slide / sliver). Alignment maps to the start,
center, or end of the edge; `offset` shifts within it (clamped on-screen); `inset` lifts
the dock off the edge for a floating bar.

- **"Bottom-right aligned"** = `edge: .bottom, alignment: .trailing`. **Floating island
  top-center** = `edge: .top, alignment: .center, inset: 12`. Vertical docks
  (left/right) lay their tiles in a column.
- **Per-display placement.** Each connected display can have its own `DockAnchor` (or
  follow a default). The dock parks when a display disconnects and returns to the same
  spot by UUID when it comes back — MacDring's connect/disconnect policy.
- **Multi-display reveal:** the edge-hover monitor knows which screen the pointer is on
  and reveals that screen's dock.

---

## 6. Domain Model

One small Codable document plus global prefs. Identity by `UUID` so items survive
rename/reorder.

```swift
struct DockDocument: Codable {        // persisted root
    var version: Int                   // schema version for migrations
    var items: [DockItem]              // pinned items, in order (running-only apps appended live)
    var anchorsByDisplayUUID: [String: DockAnchor]   // per-display placement
}

struct DockItem: Codable, Identifiable {
    let id: UUID
    var kind: DockItemKind
    var displayName: String            // overridable label
    var bookmark: Data?                // security-scoped-ready URL bookmark (apps/files/folders)
    var url: URL?                      // for .url, or fallback path
    var bundleIdentifier: String?      // for .application — match against running apps
    var folderDisplay: FolderStackStyle? // for .folder — fan/grid/list "stack"
}

enum DockItemKind: String, Codable {
    case application                   // a pinned app (shows running indicator + count)
    case file, folder                 // a document or a folder "stack"
    case url                          // a web/deeplink tile
    case separator                    // a visual divider / spacer
    case trash                        // the Trash (drop to delete; click to open; empty)
    case clock                        // the date/time widget tile  (improvement #3)
    case jettyMenu                    // the Start-menu launcher button (improvement #3)
}

enum FolderStackStyle: String, Codable { case fan, grid, list }
```

A rendered tile is the merge of (pinned items) + (running apps not already pinned),
computed by `DockModel` from `DockDocument` + `RunningAppsModel`. Running apps show a
**running indicator**; an app with multiple windows can show a count (window count is a
*later*, Accessibility-gated refinement — v1 shows running/active state only).

---

## 7. Items, indicators & interactions

| Action | Result | API (permission) |
|---|---|---|
| Click an app tile | Launch if not running; else activate (bring forward) | `NSWorkspace.open` / `NSRunningApplication.activate` (none) |
| Click a file/folder/url tile | Open it in Finder / the default app (a folder opens in Finder; its contents preview on hover) | `NSWorkspace.open` (none) |
| Drag a file onto an app tile | Open the file *with* that app | `NSWorkspace.open(_:withApplicationAt:)` (none) |
| Drag a file/app/url into the dock | Pin it as a new item | bookmark capture (none) |
| Right-click an app tile | Synthesized menu: Activate, Hide, Quit, Options ▸ (Keep in Dock, Open at Login\*), Show in Finder, Recent Documents\* | `NSRunningApplication`/`NSWorkspace`; recents via `.sfl2` parse\* (none) |
| Drag tiles | Reorder; drag out to remove | (none) |
| Click the Trash tile | Open Trash; **drop** files to delete; menu → Empty Trash | `FileManager`/`NSWorkspace` (none) |
| Hover a tile | Running app → window peek (names, or live thumbnails); folder → contents stack; optional name label | (thumbnails: Screen Recording) |
| Click the Jetty Menu tile / hotkey | Open the Start-menu launcher | (none; power cmds: Automation) |

\* Recent-documents and "Open at Login" parity are best-effort/later (the app's *own*
custom dock menu can't be read cross-process — we synthesize ours).

- **Running & launching indicators** come from `NSWorkspace.runningApplications`
  (filtered to `activationPolicy == .regular`) plus `didLaunch`/`didTerminate`/
  `didActivate`/`didHide` notifications — exactly how uBar/ActiveDock drive theirs.
- **Icons** via `NSWorkspace.shared.icon(forFile:)` / `NSRunningApplication.icon`, cached
  in an LRU (reuse Zap's `LRUImageCache` pattern).
- **Attention/bounce:** Jetty can bounce **its own** tile; it animates a **custom**
  attention pulse on another app's tile when it detects that app requesting attention
  (badge/AX state) — there's no API to bounce another app's real tile.

---

## 8. Built-in extras (improvement #3)

### 8.1 Date/Time tile (`clock`)
A dock tile that renders the current time and (optionally) date, format configurable
(12/24h, seconds, weekday, custom `DateFormatter` template). Click → open Calendar (or a
small month popover). Pure formatting logic (`ClockFormatter`) is unit-tested; the view
ticks on a coalesced timer aligned to the minute/second.

The tile's look is a `ClockFaceStyle` (Widgets ▸ Clock ▸ Face): the plain **digital**
text, a seven-segment **LCD** drawn as a whole resin sports watch in the spirit of 80s
Casios, or an analog dial — the minimal **classic** glass face, **Clock Face 2000** (a
station-style dial of our own: silvery face, rounded slate batons, orange ring second
hand), the mid-90s rainbow-era **retro Mac** wristwatch (blue studded metal bezel,
green triangle hour hand, red minute baton, yellow squiggle second hand, and a rainbow
chip — no logo), an 80s Memphis-style **Swatch** (cream dial, pastel shapes, confetti
markers, outlined hands), an early-90s translucent **jelly** watch tinted with the
accent color (rainbow dot markers), and **Color Time**, a 70s Chromachron-style dial
whose 30° hour wedge sweeps a color wheel hidden under a black dial (no hands —
deliberately approximate). Dials are drawn in `Canvas` (`AnalogClockFace`), inset so
the rim stroke stays fully inside the canvas bounds (nothing clips); digit shapes
(`SevenSegment`) and hand angles (`ClockGeometry`) are pure and unit-tested. The old
`clockAnalog` boolean migrates to `.classic`, and the retired `"swiss"` raw value maps
onto Clock Face 2000.

A **Face size** slider (Widgets ▸ Clock, 100–160%) lets a watch face float out past
the glass strip like a permanently magnified tile: the face pins to the dock edge and
grows inward, the panel gains matching across-axis headroom
(`DockLayout.clockZoomHeadroom`, pure/unit-tested — the face style/zoom are part of
the layout preference signature so the window resizes live), and hover magnification
skips a zoomed clock so the two never compound past the window bounds (the
overflow-scroll dock suspends the zoom too — its viewport clips). Horizontal
docks only — on a vertical dock the face would grow along the dock into its
neighbors. The 160% cap keeps the square dial inside the clock tile's 1.6×-wide
footprint, so no along-axis layout changes are needed.

### 8.2 The Jetty Menu (Windows-Start-style launcher)
A separate borderless panel (`JettyMenuPanel`) summoned from its dock tile or a hotkey:

- **Instant app search.** Type to filter all apps (a `/Applications` scan merged with a
  Spotlight `NSMetadataQuery` for apps anywhere), ranked by a small fuzzy scorer
  (`AppSearch`, pure + unit-tested); ↑/↓ select, ⏎ launch, `Esc` close — the same
  type-to-find ergonomics as Zap.
- **Recents & pinned.** Recently launched apps and a few user-pinned shortcuts.
- **Power commands** (`PowerCommands`): **Sleep, Restart, Shut Down, Log Out, Lock
  Screen, Empty Trash**. Implemented via AppleEvents to `loginwindow`/System Events
  (e.g. `tell application "System Events" to shut down`) or equivalents (`pmset
  displaysleepnow` for sleep/lock); each is a pure descriptor mapping
  (`PowerCommand.appleScript` / `.eventID`) so the *mapping* is unit-tested even though
  execution needs a GUI session. Destructive commands confirm first. First use prompts the
  one-time **Automation** permission for System Events.
- Styled in the same Liquid Glass language as the dock; honors Reduce Transparency.

---

## 9. Visual style — deep control (improvement #2)

Global appearance lives in `Preferences` (Zap-style `ObservableObject` over
`UserDefaults`, validated/clamped on read). Everything is **live-previewed** in Settings
and bundled into **shareable presets**.

| Setting | Type | Notes |
|---|---|---|
| Material | enum: `liquidGlass` / `glassClear` / `glassTinted` / `solid` / `gradient` | Glass variants `@available(macOS 26)`; else fall back to `NSVisualEffectView` |
| Tint color | Color (hex) | tints glass (`tintColor`) or fills solid/gradient |
| Gradient color + angle | Color + degrees | for `gradient` material (reuse Zap's `AngleDial`) |
| Background opacity | 0–1 | honored on non-glass; glass respects system |
| Icon size | 24–128 | tile size |
| Tile spacing | slider | gap between tiles |
| Corner radius | 0–32 | dock + tiles |
| Magnification | off / amount | Dock-style hover zoom (pure `MagnificationCurve`, unit-tested) |
| Indicator style | dot / bar / underline / none | running indicator look |
| Indicator color | Color | — |
| Label on hover | toggle | tile name tooltip/label |
| Auto-hide | toggle + reveal/hide delays | §4 |
| Reveal trigger | edge-hover / hotkey / both | §4 |
| Per-display dock on/off | toggle (per screen) | each display's dock can be turned off; at least one is always kept, §5 |

- **Liquid Glass** is rendered with an `NSGlassEffectContainerView` wrapping per-tile/
  panel `NSGlassEffectView` (the correct grouping so tiles sample the background once and
  can meld), behind `@available(macOS 26, *)`. On macOS 13–15 (or Reduce Transparency),
  fall back to a rounded `NSVisualEffectView` + tint. Respect
  `NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency` and the Tinted/Clear
  user setting.
- **Presets:** an `AppearancePreset` Codable bundle (mirrors Zap's `AppearancePreset` +
  built-in themes) with **Export…/Import…** to a small `.json`, plus built-ins
  (e.g. *Tahoe Glass*, *Graphite*, *Vapor*, *Midnight*). Pure encode/decode is
  unit-tested.

---

## 10. Hiding the system Dock (and restoring it)

`SystemDockController` owns this, with explicit user consent on first run:

- **Hide:** `defaults write com.apple.dock autohide -bool true`,
  `autohide-delay -float 1000`, `autohide-time-modifier -float 0`, then **`killall Dock`
  once**. The real Dock stays alive (so Mission Control / Spaces / minimize keep working)
  but is effectively off-screen.
- **Re-assert** the keys on launch, on wake (`NSWorkspace.didWake`), and on
  screen-parameter changes, because Tahoe can reset/glitch auto-hide.
- **Restore:** delete `autohide-delay`, set `autohide` back to the user's prior value
  (captured before we changed it), `killall Dock`. Exposed as **Settings → General →
  Restore system Dock** and run automatically on uninstall/quit-if-requested.
- **Read defaults via `CFPreferences`/`UserDefaults(suiteName: "com.apple.dock")`** and
  run `killall` via `Process`; all reversible, all public, no SIP, no entitlement.
- Detect if the real Dock reappears (edge hover can still trigger it on plain auto-hide)
  and offer the long-delay suppression; never inject or kill repeatedly.

---

## 11. Project Structure

Mirrors Zap/MacDring and **Xcode 16+ file-system-synchronized groups**
(`PBXFileSystemSynchronizedRootGroup`) — new files under `Jetty/` / `JettyTests/` are
picked up with no `project.pbxproj` edits. Build settings match the siblings:
`MACOSX_DEPLOYMENT_TARGET = 13.0`, `GENERATE_INFOPLIST_FILE = YES`,
`INFOPLIST_KEY_LSUIElement = YES`, `ENABLE_HARDENED_RUNTIME = YES`, `SWIFT_VERSION = 5.0`,
`PRODUCT_BUNDLE_IDENTIFIER = com.jettyapp.Jetty`.

```
Jetty/
├── Jetty.xcodeproj                  # synchronized groups; .accessory, LSUIElement, hardened runtime
├── Jetty/
│   ├── JettyApp.swift               # @main enum; NSApplication, .accessory policy
│   ├── AppDelegate.swift            # status item, bootstraps controllers, first-run consent
│   ├── Model/
│   │   ├── DockDocument.swift       # Codable root (+ schema version)
│   │   ├── DockItem.swift           # + fromFileURL/fromRunningApp factories
│   │   ├── DockItemKind.swift
│   │   ├── DockAnchor.swift         # display UUID + edge + alignment + offset + inset
│   │   ├── DockEdge.swift           # + DockAlignment
│   │   ├── AppearancePreset.swift   # Codable theme bundle + built-ins (Zap-style)
│   │   ├── PreferenceEnums.swift    # material / indicator / reveal-trigger enums
│   │   ├── ColorHex.swift           # reused from Zap
│   │   └── Preferences.swift        # UserDefaults-backed global prefs
│   ├── Store/
│   │   ├── DockStore.swift          # load/save JSON, observable, debounced atomic write + .bak
│   │   └── BookmarkResolver.swift   # bookmark ⇄ URL, staleness, broken-item handling
│   ├── Screens/
│   │   ├── DisplayRegistry.swift    # NSScreen ⇄ CGDisplay UUID, change notifications
│   │   └── DockLayout.swift         # pure anchor → frame math (revealed/hidden) — unit-tested
│   ├── Apps/
│   │   ├── RunningAppsModel.swift   # NSWorkspace running apps + launch/quit/activate observers
│   │   └── AppLauncher.swift        # NSWorkspace open/activate/openWith/hide/terminate
│   ├── SystemDock/
│   │   └── SystemDockController.swift # hide/re-assert/restore the real Dock (defaults + killall)
│   ├── Dock/
│   │   ├── DockController.swift      # the brain: merges items, drives panels + reveal/hide
│   │   ├── DockPanelController.swift # one auto-hiding NSPanel per display (+ edge-hover monitor)
│   │   ├── DockModel.swift           # observable rendered-tile state + callbacks
│   │   ├── DockView.swift            # SwiftUI: GlassEffectContainer of tiles + widgets
│   │   ├── DockTileView.swift        # one tile: icon, indicator, magnification, drop target
│   │   ├── MagnificationCurve.swift  # pure Dock-style hover-zoom math (unit-tested)
│   │   └── EdgeHoverMonitor.swift    # global mouse monitor → which screen edge is hovered
│   ├── Widgets/
│   │   ├── ClockWidgetView.swift     # date/time tile (digital text + face dispatch)
│   │   ├── AnalogClockFace.swift     # Canvas dials: classic/face2000/retroMac/memphis/jelly/colorTime
│   │   ├── LCDClockFace.swift        # Canvas seven-segment retro LCD face
│   │   ├── SevenSegment.swift        # pure digit→segments lookup (unit-tested)
│   │   ├── ClockGeometry.swift       # pure hand-angle/polar math (unit-tested)
│   │   └── ClockFormatter.swift      # pure time/date formatting (unit-tested)
│   ├── Menu/
│   │   ├── JettyMenuController.swift  # the Start-menu launcher panel
│   │   ├── JettyMenuView.swift        # search field + results + power row
│   │   ├── AppSearch.swift            # pure fuzzy app filter/rank (unit-tested)
│   │   ├── AppIndex.swift             # /Applications scan + Spotlight (NSMetadataQuery)
│   │   └── PowerCommands.swift        # sleep/restart/shutdown/logout/lock/empty-trash (pure mapping + exec)
│   ├── Hotkeys/
│   │   ├── CarbonHotkey.swift         # optional toggle hotkeys (no Accessibility) — reused
│   │   └── KeyCodes.swift             # reused
│   ├── Settings/
│   │   ├── SettingsWindowController.swift
│   │   ├── SettingsView.swift
│   │   ├── GeneralView.swift          # launch at login, hide/restore Dock, reveal triggers
│   │   ├── AppearanceView.swift       # material/size/spacing/radius/indicator + presets + live preview
│   │   ├── ItemsView.swift            # manage pinned items + widgets, per-display placement
│   │   ├── MenuView.swift             # Jetty Menu config (power cmds, recents)
│   │   ├── PermissionsView.swift      # reports Accessibility/Screen-Recording/Automation status (for later features)
│   │   ├── AngleDial.swift            # gradient angle picker — reused from Zap
│   │   └── AboutView.swift
│   ├── Updates/
│   │   ├── UpdateChecker.swift        # GitHub release check + alert (reused from Zap)
│   │   ├── GitHubReleaseClient.swift
│   │   ├── GitHubRelease.swift
│   │   ├── UpdateDownloader.swift
│   │   └── SemanticVersion.swift
│   ├── Common/
│   │   ├── VisualEffectView.swift     # NSVisualEffectView wrapper (reused)
│   │   ├── GlassBackground.swift      # NSGlassEffectView (macOS 26) with VisualEffect fallback
│   │   ├── ActivationPolicy.swift     # shared .regular↔.accessory revert guard (reused)
│   │   └── LRUImageCache.swift        # icon cache (reused from Zap)
│   ├── Jetty.entitlements             # hardened runtime; no sandbox; (later) AppleEvents
│   └── Resources/
│       └── Assets.xcassets            # AppIcon, AccentColor (Info.plist generated)
├── JettyTests/
│   ├── DockLayoutTests.swift          # anchor → frame across edges/alignments/resolutions + hidden frames
│   ├── DockAnchorTests.swift          # offset/inset clamping + Codable
│   ├── DockDocumentCodableTests.swift # encode/decode + forward-compat
│   ├── DockModelTests.swift           # pinned+running merge / dedup / ordering / indicators
│   ├── MagnificationCurveTests.swift  # hover-zoom falloff
│   ├── ClockFormatterTests.swift      # 12/24h, seconds, custom templates
│   ├── AppSearchTests.swift           # fuzzy rank / filter / selection movement
│   ├── PowerCommandTests.swift        # command → descriptor mapping + confirmation flags
│   ├── AppearancePresetTests.swift    # preset Codable + built-ins round-trip
│   ├── PreferencesTests.swift         # defaults, clamping
│   ├── ColorHexTests.swift            # hex ⇄ color
│   ├── SemanticVersionTests.swift     # version parse/compare
│   └── GitHubReleaseTests.swift       # release JSON decode + asset pick
├── scripts/
│   ├── build.sh                       # lkm-build stub (BUILD_KIND=xcode)
│   └── release.sh                     # lkm-release stub (RELEASE_KIND=xcode)
├── .github/workflows/
│   ├── ci.yml                         # build + test (macos, Xcode pinned, CODE_SIGNING_ALLOWED=NO)
│   └── release.yml                    # tag v* → Release build, ad-hoc sign, zip+dmg, GH Release
├── PLAN.md  ├── README.md  └── AGENTS.md
```

---

## 12. Permissions, Signing & Distribution

- **Core dock: no permissions.** Apps/launch/icons/indicators/drag-to-open use
  `NSWorkspace`; reveal uses a global **mouse** monitor + Carbon hotkeys; hiding the Dock
  is a `defaults` write. Zero TCC prompts to get a fully working dock.
- **Power commands:** first use prompts **Automation** (AppleEvents to System Events) —
  per-target, one-time. Sleep/lock can avoid even that via `pmset`.
- **Later features (opt-in):** window peeking / minimize/raise needs **Accessibility**
  (`AXIsProcessTrustedWithOptions` guided prompt); live previews need **Screen Recording**
  (ScreenCaptureKit, `NSScreenCaptureUsageDescription`). The **Permissions** pane reports
  status and deep-links to the right System Settings panes; everything degrades gracefully
  when declined.
- **`LSUIElement = true`**, `.accessory` policy: no Dock icon; Settings temporarily flips
  to `.regular` and back (shared `ActivationPolicy` guard).
- **Launch at login** via `SMAppService.mainApp` (status surfaced in-app; handle
  `.requiresApproval`).
- **Distribution:** Developer ID + notarization + hardened runtime, non-sandboxed,
  shipped as a signed DMG/zip from GitHub Releases (CI publishes an **unsigned ad-hoc**
  build for dev, same as Zap/MacDring; real signing is the maintainer step). **No App
  Store** (sandbox precludes the later AX features). Private symbols (only ever
  `_AXUIElementGetWindow`, `AXStatusLabel` in later milestones) are weak-imported and
  isolated — they don't block notarization.

---

## 13. Implementation Phases / Milestones

> **Status:** **v1 (Phases 1–8) shipped**, and it **builds on macOS 26 with Xcode 26**.
> A large batch of post-v1 polish has since landed too: per-display position UI, folder
> stacks (grid/list/fan), in-dock reorder + drag-out-to-remove (with the *poof*),
> continuous pointer-tracking magnification, per-tile accent glow, customizable global
> shortcuts, rename / custom-icon per item, retro flourishes (decorations + CRT), the
> Jetty-Menu command bar (calculator, unit/currency conversion, web-search fallback,
> quick toggles), a family of **info tiles** (battery, weather, world clock, Pomodoro,
> CPU/RAM with an optional time-series graph + network throughput, and an **opt-in
> now-playing** tile via an isolated MediaRemote bridge), per-display dock on/off
> toggles, horizontal overflow-scroll, and the app icon (Phase 12). **Window peeking
> (Phase 9) and live previews (Phase 10) have since shipped** as opt-in features
> (window names need no permission; live thumbnails use ScreenCaptureKit). Genuinely
> still later: badge / unread mirroring (Phase 11) and taskbar/multi-row + Stage-Manager
> tuning (Phase 12). Pure logic is unit-tested; windowing, multi-monitor, reveal,
> Dock-hide, Liquid Glass, drag-and-drop, and power commands still want manual GUI
> verification on each release (same policy as the siblings).
>
> **For the live project status and the open backlog, see [`REVIEW.md`](REVIEW.md).**

1. **Skeleton** — Xcode project (synchronized groups, `.accessory`, `LSUIElement`,
   hardened runtime), menu-bar `NSStatusItem`, Settings window, `Preferences` + `ColorHex`,
   reused `Updates/` + `Common/`.
2. **Model & store** — `DockDocument`/`DockItem`/`DockAnchor` Codable (forward-compatible);
   `DockStore` atomic/debounced JSON + `.bak`; `BookmarkResolver`.
3. **Displays & layout** — `DisplayRegistry` (UUID mapping + change notifications) and the
   pure, unit-tested `DockLayout` (edge × alignment × offset × inset; revealed/hidden).
4. **Dock panel & reveal** — borderless non-activating per-display `NSPanel`;
   `EdgeHoverMonitor` (global mouse) + Carbon hotkey reveal/hide; auto-hide animation;
   pinned/always-shown option.
5. **Tiles & apps** — `RunningAppsModel` (+ notifications); merged pinned+running
   `DockModel`; `DockTileView` with icon cache, running indicator, magnification; click to
   launch/activate; drag-to-open; drag-to-pin/reorder; synthesized right-click menu; Trash.
6. **Hide the real Dock** — `SystemDockController` (construe + re-assert + one-click
   restore).
7. **Extras** — `ClockWidget` (date/time tile) and the `JettyMenu` launcher (app search +
   recents + power commands).
8. **Appearance & settings** — Liquid Glass (`GlassBackground`, macOS 26 + fallback),
   material/size/spacing/radius/indicator controls, **presets** import/export with live
   preview; full Settings (General/Appearance/Items/Menu/Permissions/About);
   `SMAppService` launch-at-login; GitHub updater wired.
9. **Window peeking** (later) — Accessibility-gated per-app window lists, click-to-raise,
   minimize/restore (`AXUIElement` + weak `_AXUIElementGetWindow`), with a guided prompt.
10. **Live previews** (later) — ScreenCaptureKit hover thumbnails (Screen Recording),
    cache last on-screen frame for minimized windows; opt-in.
11. **Badge mirroring & media** (later) — best-effort `AXStatusLabel`/`lsappinfo` unread
    counts; optional now-playing tile (behind feature flags; private-API-aware).
12. **Polish & release** — generated app icon, taskbar/multi-row mode, Spaces/Stage
    Manager tuning, on-device GUI verification, Developer ID signing + notarization.

> Pure logic (layout math, anchor coding, Codable + forward-compat, tile merge,
> magnification curve, clock formatting, app-search ranking, power-command mapping, prefs,
> presets, semver, release JSON) is unit-tested. Windowing, multi-monitor, reveal,
> Dock-hide, Liquid Glass, drag-and-drop, and power commands need a real macOS GUI session
> and are verified manually.

---

## 14. Key Risks & Edge Cases

- **Auto-hide trick is OS-version-fragile** (Tahoe 26.0–26.0.1 regressions). *Mitigation:*
  re-assert defaults on launch/wake/screen-change; detect the Dock reappearing; ship a
  one-click restore; document honestly.
- **Focus theft.** The dock + Jetty Menu must be **non-activating** panels; launching an
  item keeps the user's frontmost context. Verify clicking a tile never reorders app focus.
- **Overlap is intended, not a bug.** Because we don't reserve space, the dock floats over
  content on reveal. Make auto-hide snappy and the resting state unobtrusive so overlap is
  never annoying; offer a pinned-with-inset "island" for users who want it always visible.
- **Fullscreen & Stage Manager.** Overlay there is best-effort; default to hide + hover/
  hotkey reveal; never rearrange.
- **Display disconnect/reconnect & resolution change.** Park by UUID, restore exactly;
  fractional/aligned anchors survive resolution changes (MacDring's model).
- **Many apps / many tiles.** Lazy-render, cache icons (LRU), scroll/condense past a max
  size; magnification stays allocation-light on the hot path (Zap's lesson: reuse the
  model, avoid full SwiftUI rebuilds).
- **Document corruption.** Atomic writes + one `.bak`; load failure degrades to "no pinned
  items" with a restore offer, never a crash.
- **Borderless-panel drawing stalls** after long compositor uptime — recycle the panel
  when hidden (proven in Zap).
- **Power commands are destructive.** Confirm Shut Down/Restart/Log Out; handle denied
  Automation (`errAEEventNotPermitted`) with a clear pointer to System Settings.
- **Private-API drift** (later milestones). Weak-import, feature-flag, fall back to public
  APIs, re-test each macOS beta.

---

## 15. Competitive Landscape & Differentiation

| Tool | What it is | Mechanism | Gap Jetty fills |
|---|---|---|---|
| **uBar** ($30) | The gold-standard full dock + Windows-taskbar mode | autohide trick + AX + ScreenCaptureKit | dated aesthetic; not Liquid-Glass-native; limited free-form positioning |
| **ActiveDock 2** (~$17–54) | Safe full replacement + Launchpad-style launcher | no SIP, notarized, Tahoe-ready | less window UX; closed-source feel |
| **DockDoor** (free, OSS) | *Enhancer*: hover previews + alt-tab on the real Dock | AX + ScreenCaptureKit | not a replacement; no positioning/widgets |
| **cDock** (legacy) | Dock themer | injects into Dock.app — **needs SIP off** | dead on Apple Silicon/Tahoe |
| **Docky** (OSS) | Powerful native-feel replacement | **private SkyLight/CGS SPI** | App-Store-ineligible, update-fragile |
| **Dockey** (free) | GUI for `defaults` Dock tweaks | `defaults` only | not a dock at all |

**Jetty's niche:** a **SIP-safe, public-API, Liquid-Glass-native** dock that wins on the
axes the incumbents under-serve — **free-form positioning** (edge × alignment × offset ×
floating inset, per display), **deep visual control with shareable presets**, and
**built-in date/time + a Start-menu launcher with search and power commands** — with the
*later* option to add DockDoor-class window peeking. Pricing, if commercialized, fits the
proven one-time **$15–35** band; but Jetty's first job is to be the best *free-positioning,
beautiful, no-permission* dock in the family alongside Zap and MacDring.

---

*Sources for the feasibility analysis (June 2026): uBar support docs (autohide trick; AX
window management); ActiveDock FAQ (no SIP, notarized, macOS 26); DockDoor (open-source AX
+ ScreenCaptureKit architecture); Apple developer docs & WWDC25 on Liquid Glass
(`NSGlassEffectView`, `.glassEffect`); Apple Feedback FB9985546 (no visibleFrame-reservation
API); Apple DTS guidance that notarization is not App Review; macOS 26 Dock auto-hide
regression reports (26.0–26.1). Adversarially fact-checked: "uBar proves a full
*replacement*" was corrected to "a co-resident utility"; "reading another app's badge" was
corrected to "no documented API, but the undocumented AX `AXStatusLabel` works with
polling."*
