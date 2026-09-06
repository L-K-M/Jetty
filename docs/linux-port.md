# Porting Jetty to Ubuntu Linux — Research & Findings

*Research completed 2026-09-05/06, from a file-by-file read of the codebase (111 app
files, 15,254 LOC; 33 test files, 3,326 LOC) plus verification of the Linux ecosystem
against primary sources, and an adversarial pass that tried to refute every
load-bearing claim. Confidence markers where it matters: **[V]** verified against a
named primary source, **[I]** inference, **[U]** unverified.*

*This document is Jetty's counterpart to Pict's [`docs/linux-port.md`](https://github.com/L-K-M/Pict/blob/main/docs/linux-port.md).
The shared background — desktop-shell constraints, the Swift-on-Linux toolchain
report, UI-framework evaluations, packaging — lives in the Top Drawer repo under
[`docs/linux-port/`](https://github.com/L-K-M/TopDrawer/tree/main/docs/linux-port)
and is not repeated here. The companion implementation plan is
[`linux-port-plan.md`](linux-port-plan.md).*

---

## The one-paragraph answer

**Yes — and Jetty is the best-suited of the three apps, for a reason worth stating
plainly: Jetty's hardest-won macOS invariants are, on Wayland, single protocol
values.** "Never reserve screen space" is `set_exclusive_zone(0)`. "Float over
content, on every Space" is `layer = OVERLAY`. "A tile click must never steal focus"
is `keyboard_interactivity = NONE`. "Anchor to an edge with an alignment, an offset
and an inset, per display" is `set_anchor` + `set_margin` + `set_monitor`. Roughly
200 lines of the subtlest code in the app — `DockPanelController`'s reveal-zone,
hard-edge and display-seam pointer heuristics — are **deleted rather than ported**,
because a per-output sliver surface's pointer-enter event is authoritative where a
global mouse monitor had to guess. About **45% of Jetty's app code and 95% of its
test code** move to Linux, and the extraction that gets them there (a `JettyCore`
SwiftPM package) leaves the Mac app better factored on its own terms. The catch is
the same one Top Drawer hit and it is not a Jetty problem: **stock GNOME Wayland —
Ubuntu's default desktop — will not let any client process be a dock**, so shipping
to most Ubuntu users requires a GNOME Shell extension alongside the app, exactly as
Ubuntu's own dock is one.

## Framing: what a Linux Jetty is

On macOS, Jetty exists to stand in for a Dock that cannot be replaced or removed —
so it hides Apple's Dock and floats its own alongside. On Linux there is no
single protected Dock process; there is a *desktop-environment-dependent* panel
(Ubuntu's own dock is a Shell extension; KDE's is a Plasma panel; wlroots
compositors usually have no panel at all). So the port is really three products:

1. **`JettyCore`, the shared logic package** — the document model, the store, the
   layout math, the tile merge, the magnification curve, the command bar's
   evaluator/converter/search, the updater. Genuinely portable today, and
   extracting it is the "Step 1 that benefits macOS too" move the Top Drawer plan
   makes.
2. **`jettyd` + `jetty-shell` on layer-shell compositors** (KDE Plasma, Sway,
   Hyprland, labwc, Wayfire, COSMIC, Mir) — where Jetty is a *near-perfect* fit,
   in several respects better than on macOS.
3. **A GNOME Shell extension tier** for stock Ubuntu — mandatory, not optional,
   because click-to-activate a running window is impossible for a client there, and
   a dock whose tiles cannot raise a window is not a dock.

The "hide the system Dock" feature also changes character. On Linux it becomes
"stand down the desktop's own panel", which is per-desktop: `gnome-extensions
disable ubuntu-dock@ubuntu.com` on Ubuntu GNOME (per-user GSettings), a Plasma
panel setting on KDE, and usually nothing at all on wlroots. **[V]** That means the
shipped **Restore System Dock** promise has to be re-implemented per tier rather
than ported — see [Correction 12](#verification-appendix).

## What the inventory found

Portability buckets over 15,254 lines of app code (tests excluded), from a
file-by-file read:

| Bucket | Meaning | LOC | % |
|---|---|---:|---:|
| **P1** | Pure logic; compiles on Linux today (modulo `CoreGraphics` → `Foundation` for CG value types) | 2,425 | 16% |
| **P2** | Foundation-only; needs a named check or small migration (Combine, a corelibs hole, a formatter difference) | 1,808 | 12% |
| **P3** | Platform service behind a seam — logic survives, backend swaps | 2,678 | 18% |
| **P4** | UI needing a Linux frontend | 7,614 | 50% |
| **P5** | macOS-only concept; delete or stub | 729 | 5% |

**Shareable today: P1+P2+P3 = 6,911 LOC, ~45% of the app.** The `JettyCore`
extraction moves most of it; the rest is seam implementations.

Per subsystem:

| Subsystem | LOC | P1 | P2 | P3 | P4 | P5 |
|---|---:|---:|---:|---:|---:|---:|
| `Model/` + `Store/` | 1,864 | 768 | 685 | 411 | 0 | 0 |
| `Menu/` (Jetty Menu / command bar) | 1,900 | 544 | 397 | 296 | 604 | 59 |
| `Widgets/` (the info tiles) | 2,560 | 195 | 337 | 395 | 1,633 | 0 |
| `Dock/` render half | 1,394 | 219 | 124 | 137 | 905 | 9 |
| `Dock/` windowing half | 1,923 | 32 | 0 | 38 | 1,853 | 0 |
| `Screens/` + `Stacks/` | 936 | 434 | 51 | 212 | 239 | 0 |
| `Apps/` + `SystemDock/` | 923 | 29 | 0 | 774 | 41 | 79 |
| `Updates/` + `Hotkeys/` + `Windows/` | 1,530 | 204 | 168 | 259 | 644 | 255 |
| `Settings/` | 1,265 | 0 | 0 | 0 | 1,065 | 200 |
| `Common/` + `Icons/` + app lifecycle | 959 | 0 | 46 | 156 | 630 | 127 |

**Tests are the standout**: of 3,326 test LOC across 33 files, **~3,160 (95%)** are
portable — 1,320 unchanged, the rest behind the same seams the app needs. Jetty's
house rule of keeping the logic backbone pure is what makes this port tractable, and
the existing suites become the conformance tests for every Linux adapter.

Highlights that port **unchanged**: the whole of `DockLayout` (362 LOC of pure
geometry), `MagnificationCurve`, `DockModel.makeSlots`/`makeTiles`,
`DockContextMenuPlacement`, `ClockFormatter`, `ClockGeometry`, `SevenSegment`,
`AppSearch`, `ExpressionEvaluator`, `UnitConverter`, `MenuCommand.match`,
`FolderStack`'s ordering/geometry, `SemanticVersion`, `GitHubRelease`, the
`PowerCommand` catalogue, and `DockDocument`'s lenient-decode machinery.

**Empirically confirmed, not just claimed:** 26 of those files (2,415 LOC) were
compiled as a SwiftPM library on Swift 6.3.3 / Ubuntu 24.04 during this research,
needing only `#if canImport(CoreGraphics)` on five files,
`#if canImport(FoundationNetworking)` on three, `#if canImport(AppKit)` around one
line of `DockItem.swift`, and Top Drawer's existing `ObservationCompat` shim. **[V]**

## The desktop wall (and where Jetty stands in it)

This is unchanged from [Top Drawer's `02-desktop-constraints.md`](https://github.com/L-K-M/TopDrawer/blob/main/docs/linux-port/02-desktop-constraints.md)
and was **re-verified on 2026-09-05**: nothing has moved. A normal Wayland client
cannot position windows at screen coordinates, stay above others, read the global
pointer, enumerate windows, or grab global keys. `wlr-layer-shell` is the exception
and **Mutter refuses it** — mutter#973 and gnome-shell#1141 remain closed. **[V]**
`ext-layer-shell` has been a draft for six years; `xx-zones` has no implementations;
the `InputCapture` portal can detect an edge crossing only by seizing all input
behind a consent dialog, and still cannot place a surface. **[V]**

| Capability | A: stock GNOME | B: GNOME + our extension | C: KDE | D: wlroots/COSMIC/Mir | E: X11/XWayland |
|---|:--:|:--:|:--:|:--:|:--:|
| Dock at an edge, chosen display | ❌ | ✅ | ✅ | ✅ | ✅ |
| Never reserves space / floats over content | ❌ | ✅ | ✅ | ✅ | ⚠️ |
| Visible over fullscreen | ❌ | ✅ | ✅ (overlay layer only) | ✅ (overlay layer only) | ⚠️ |
| Pointer-at-edge reveal | ❌ | ✅ barriers | ✅ sliver | ✅ sliver | ⚠️ |
| Click a tile without stealing focus | ❌ | ⚠️ manual | ✅ | ✅ | ✅ |
| Click-to-activate/minimise a running app | ❌ | ✅ exact | ✅ | ✅ | ✅ |
| Running-app dot | ⚠️ heuristics | ✅ exact | ✅ | ⚠️ mixed | ✅ |
| Global hotkeys | ⚠️ portal 25.10+ | ✅ no dialog | ✅ | ⚠️ config | ✅ |
| Window peek / live previews | ❌ | ✅ | ✅ | ⚠️ | ⚠️ |

**Verdict for stock GNOME is binary: ship a GJS Shell extension, or ship nothing.**
Ubuntu itself answers the question the same way — `ubuntu-dock@ubuntu.com` is a
Shell extension shipped in `gnome-shell-ubuntu-extensions` (50.26.04.7ubuntu in
26.04, and now in **main**, not universe). **[V]** The extension toolkit
(`move_resize_frame`, `make_above`, `stick`, `Meta.Barrier`) is public and still used
by gnome-shell itself, so the mechanism is sound; price it as a permanently
maintained mini-project, one compatibility release per GNOME cycle (GNOME 51 lands
2026-09-16). **[V]**

**Do not build an X11/XWayland tier for Jetty.** It buys visible, clickable tiles
while killing the three behaviours that define Jetty — hover-reveal, hotkeys, and
over-fullscreen. It is a distraction, not a foundation.

## Jetty's design decisions, expressed in Wayland

This is the finding that makes the port attractive rather than merely possible.
Every row is `AGENTS.md`'s "Critical Constraints" section restated as protocol.

| `AGENTS.md` invariant | macOS mechanism | Layer-shell mechanism |
|---|---|---|
| Don't reserve screen space | never touching `visibleFrame` (convention) | `set_exclusive_zone(0)` — enforced by the compositor |
| Float over content, all Spaces, over fullscreen | `level = .popUpMenu` + `collectionBehavior` | `layer = OVERLAY` — layer surfaces are output-scoped, not workspace-scoped |
| Panels must stay non-activating | `.nonactivatingPanel` + `becomesKeyOnlyIfNeeded` + `acceptsFirstMouse` override | `keyboard_interactivity = NONE` |
| Jetty Menu's deliberate focus hand-off | briefly activates, hands back on close | its **own** layer surface at `ON_DEMAND`, dock stays `NONE` |
| Placement is edge × alignment × offset/inset, per display | `DockLayout.revealedFrame` against `visibleFrame` | `set_anchor` + `set_margin` + `set_monitor` |
| Reveal on pointer at the screen edge | global mouse monitor + reveal-zone heuristics | a 1–2 px sliver surface; its `enter` event *is* the trigger |
| Liquid Glass, honouring Reduce Transparency | `NSGlassEffectView` / `NSVisualEffectView` | translucent flat colour; optional KWin blur — see below |

Two behaviours do **not** become declarative and must be re-implemented as they
already are on macOS — which is fortunate, because the macOS code already solved
them the layer-shell-friendly way:

- **The reveal slide** animates a content-layer transform inside a fixed window
  (`DockPanelController.applyRevealState`), never the window frame. On Linux a
  client cannot move its own surface either, so the same trick is *forced*: a
  `GskTransform` on a `GtkFixed`'s children, driven by
  `gtk_widget_add_tick_callback`. Never `gtk_layer_set_margin` per frame — that
  reconfigures compositor-side on every frame.
- **Magnification headroom** is pre-allocated in `DockLayout.contentSize` rather
  than resized per frame. Keep it that way: size the surface once, scale
  pre-rasterised `GdkTexture`s inside it. Re-rasterising a dozen tiles per frame in
  cairo will not hold 120 Hz.

## Subsystem findings

### The dock surface — `jetty-shell` on GTK4 + gtk4-layer-shell

Build on **direct GTK4 C interop from Swift**, not SwiftCrossUI or Adwaita-for-Swift.
Every hard requirement lives below any Swift framework: layer-shell init/anchor/
layer/margin/monitor/keyboard-mode, `gdk_surface_set_input_region` for
click-through-while-hidden, `gtk_fixed_set_child_transform` for magnification, a
tick-callback animation loop, `GtkDropTarget` for Nautilus drops, PangoCairo for
synchronous text measurement (the analogue of Jetty's `fittingSize` reads), and
`gdk_memory_texture_new` for PictKit icons. SwiftCrossUI's GTK backend supplies none
of them and still has no drag-and-drop (#546, open). **[V]** Top Drawer already
ships the `CGtk4` / `CGtkLayerShell` systemLibrary targets and a working
layer-shell frontend — copy them.

Packaging reality: **gtk4-layer-shell is absent from Ubuntu 24.04's archive**
(verified here: `libgtk4-layer-shell-dev` is not in noble; only the GTK3-era
`libgtk-layer-shell-dev` 0.8.2, which is a different library — do not confuse them).
It is `1.0.4-2` in 25.10 and `1.3.0-1` in 26.04, both **universe**. **[V]**
**Baseline Ubuntu 26.04 LTS**; on 24.04 build from source (Top Drawer's Linux CI
already does exactly this, pinned to upstream `v1.3.0`) or vendor it into the `.deb`
(it is MIT).

### The app model — enumerate, launch, indicate

- **App index**: a real `DesktopEntry` parser over the union of
  `$XDG_DATA_HOME/applications`, `$XDG_DATA_DIRS/applications`,
  `/var/lib/snapd/desktop/applications` and both Flatpak export dirs, deduped by
  desktop-file ID, honouring `NoDisplay`/`Hidden`/`OnlyShowIn`/`NotShowIn`/`TryExec`
  and the spec's locale ladder. **This belongs in PictKit**, next to the existing
  `DesktopEntryRewriter`/`DesktopOverrideSync`: three apps need it (Jetty, Top
  Drawer's LP-19, the Pict editor), and it retires the documented best-effort
  desktop-ID guess in `DesktopOverrideSync.overrideFilename(forSystemPath:)`.
- **Launching**: parse `Exec`, expand field codes, hand the argv to
  `systemd-run --user --quiet --scope --slice=app.slice --unit=app-jetty-<id>-<rand>.scope`.
  Boring, never invokes `sh`, keeps launched apps alive when the dock stops, and —
  because the scope name carries the app ID — makes the stock-GNOME running dot
  *exact* for everything Jetty itself launched.
- **Running state and activation**: an `AppShell` protocol with five verbs
  (`runningApps`, `windows(of:)`, `activate`, `minimize`, `close`), implemented four
  times — GNOME extension over private D-Bus (`Shell.AppSystem`/`WindowTracker`, the
  same data GNOME's own dash dots use), plasma-window-management on KDE,
  wlr-foreign-toplevel-management on wlroots, EWMH on X11 — plus a fifth, honestly
  degraded "no shell" implementation so Jetty is installable on stock GNOME before
  the extension exists, with peek and minimise greyed out.
- **Icons**: PictKit's ladder already works on Linux. Rung 4 (`NSWorkspace.icon`)
  becomes freedesktop Icon Theme lookup — which is Pict's LP-24a, a prerequisite
  Jetty now has a second reason to want.

### The info tiles

This is the one subsystem entirely independent of the desktop wall, so it can be
built, tested and merged before any tier decision. Four seams:

| Tile | macOS | Linux |
|---|---|---|
| Battery | `IOKit.ps` | UPower on the system bus (`/org/freedesktop/UPower/devices/DisplayDevice`), `/sys/class/power_supply` as explicit fallback |
| CPU/RAM/network | `host_statistics64`, `getloadavg`, `AF_LINK` `getifaddrs` | `/proc/loadavg` (`getloadavg` ports unchanged), `/proc/meminfo`, `/proc/net/dev` |
| Now playing | private MediaRemote via `dlopen` | **MPRIS2** over the session bus — a published spec, no private API, and free `PlayPause`/`Next`/`Previous` |
| Weather | HTTP (already) | same code + `FoundationNetworking`; no geolocation to replace — coordinates are already preferences |
| Pomodoro sleep/wake | `NSWorkspace.willSleep`/`didWake` | logind `PrepareForSleep(b)`; use `CLOCK_BOOTTIME` for elapsed time |

`SystemStats.Battery`, `batterySymbol(percent:)`, `isLowBattery(percent:isPlugged:)`,
`LiveSystemStats.throughput`, the history ring, and `NowPlayingService.parse`'s shape
all survive verbatim behind these seams.

### Trash, stacks, and file watching — a net deletion

The Linux port **removes** code here. TCC has no analogue, so `TrashStateResolver`,
`FinderAutomation`, `AppleScriptRunner`'s trash use and the Permissions-pane
Finder-Automation row (~110 LOC, plus a user-facing permission story that took three
attempts to get right per `TRASH.md`) all disappear: trash state becomes one
unprivileged `readdir`. The icon saga disappears too — `user-trash` /
`user-trash-full` are spec'd names every theme ships.

Split along the write/read seam: **shell out to `gio trash <path>`** (glib's
`g_local_file_trash` correctly implements topdir detection, sticky-bit validation,
`O_CREAT|O_EXCL` collision naming and relative-vs-absolute `Path` — do not
reimplement it), and do everything else in pure Swift (discover trash dirs from
`/proc/self/mountinfo` plus the spec's two per-volume forms; count with one
`readdir`; empty by deleting `files/` + `info/` contents; open via
`org.freedesktop.FileManager1.ShowFolders(["trash:///"])`). Keep `TrashLocations`'
shape — candidates / existing / watchable, with per-volume dirs watched via their
parents — and change only the path formulas.

Note `FileManager.trashItem(at:)` **does not exist on Linux** (compile error, not a
stub) and `.trashDirectory` maps to `~/.Trash`, not the spec location. **[V]**

For the watch, **copy** PictKit's inotify pattern into Jetty rather than reusing
`IconStoreWatcher` — it is named for and coupled to the icon store, it watches one
directory where `TrashMonitor` needs N with dynamic add/drop, and PictKit's public
surface is a three-app compatibility commitment. Make one structural change while
copying: **one inotify instance with a `[wd: path]` map**, not one per path
(`max_user_instances` is 128).

### Hotkeys, power, tray

- **Hotkeys**: one `HotkeyBinder` protocol, four implementations, chosen by
  *probing* not by desktop name — extension keybinding (works on every GNOME
  including 24.04, no dialog), GlobalShortcuts portal (KDE, and GNOME without the
  extension), compositor config + a `jetty-cli` verb (sway), GSettings
  custom-keybindings (documented, never auto-written). On 24.04 the portal's
  expected error is `UnknownMethod` — probe by calling.
- **Migration**: migrate off `keyLabel`, not `keyCode`. A pure
  `LinuxHotkeyTranslator` inverts `HotkeyBinding.label(for:)`'s closed glyph set into
  keysym names; add an optional `keySymbol: String?` so Linux-recorded bindings
  round-trip a prefs file that travels back to a Mac.
- **Power**: keep Jetty's existing shape — make `PowerCommand.linuxAction` a pure
  value beside `appleScript`, so the runner stays thin and the mapping stays
  unit-tested. Four of six commands go to `org.freedesktop.login1.Manager` with no
  desktop branching and no permission, and its `Can*` probes let Jetty grey out
  unavailable items — a capability check macOS never gave us. Lock Screen uses
  `login1.Session.Lock()`; it must **never** use
  `org.freedesktop.ScreenSaver.Lock()`, a declared-but-unimplemented stub on GNOME —
  the exact Linux restatement of the `SACLockScreenImmediate` lesson already recorded
  in `PowerCommands.swift`.
- **Tray**: `NSStatusItem` → StatusNotifierItem over D-Bus, hand-rolled (GTK4 removed
  `GtkStatusIcon`). Ubuntu enables the AppIndicator extension by default; on other
  GNOME installs it must be present or the tray simply does not appear.

## Build, package, ship

- **Layout**: a root `Package.swift` (swift-tools 5.9, matching `SWIFT_VERSION = 5.0`)
  with a `Jetty` library target at path `Jetty` and a curated `sources:` list; macOS
  keeps building through `Jetty.xcodeproj` and never resolves the manifest. Anything
  genuinely Linux-only lives in a second manifest at `linux/Package.swift` that
  path-depends on the root package and PictKit — exactly Top Drawer's shape.
  **This is what neutralises the file-system-synchronized-group trap**: any new
  `.swift` file under `Jetty/` is auto-added to the Xcode target, so Linux-only code
  must live outside `Jetty/` or carry a whole-file `#if os(Linux)`.
- **Combine**: take Top Drawer's merged `ObservationCompat` shim, not a migration.
  Jetty's Combine surface is 96 `@Published` / 16 `ObservableObject` but only **6**
  `.sink` calls; converting 15 types would be a large macOS-visible diff for zero
  Linux benefit.
- **`.deb`**: static-link the Swift runtime (`--static-swift-stdlib`) — do not bundle
  `.so`s and do not depend on Ubuntu's `swiftlang` (wrong version, wrong ABI story).
  Verified working, including HTTPS `URLSession`, at ~56 MB stripped. **[V]**
- **CI**: `container: swift:6.3-noble`, plus Top Drawer's existing composite action
  that builds gtk4-layer-shell from source. CI can build the frontend but not run it
  (no compositor); everything else — core, daemon, D-Bus under `dbus-run-session` —
  is genuinely testable.

## SF Symbols

Jetty references only **~31 distinct SF Symbols** (Top Drawer had ~300), so the
mapping table is small. They cannot ship on Linux for licence reasons; map to
freedesktop/Adwaita symbolic names behind an `IconName` abstraction introduced on
macOS first. Note the trap the adversarial pass caught: the *fallback* glyphs for
"no battery" and "nothing playing" are themselves SF Symbols, so the degraded paths
need Linux assets too.

## What we give up, honestly

- **Stock GNOME without our extension gets no dock.** There is no engineering answer
  to this, only the extension or a different desktop.
- **`hideDistance` has no Wayland analogue on any tier** — a client sees pointer
  events only over its own surfaces. Retire it on Linux or fold it into the hide
  delay. Do **not** fake it by inflating the input region; that makes a band of the
  user's desktop unclickable.
- **Liquid Glass** → translucent flat colour. KWin has a blur protocol; GNOME has
  none.
- **Window peek's live thumbnails** need the extension or screencopy; the
  permission-free window-*name* mode degrades to whatever the tier's toplevel
  protocol offers.
- **macOS-recorded hotkeys** need one re-record (or the translator's best effort).
- **Drag-pasteboard sniffing** for reveal-during-drag: the macOS `DragRevealSensorView`
  maps onto a `GtkDropTarget` on the sliver, which is close but not identical.

## Verification appendix

Every load-bearing claim was handed to an adversarial agent instructed to *refute*
it against primary sources. Two domains completed in the first pass; the corrections
below changed the plan and are folded into the text above.

1. **Overlay vs fullscreen — the reasoning was wrong and the corollary matters.**
   The protocol's "fullscreen surfaces are typically rendered at the top layer"
   sentence is non-normative and cannot carry the claim. The conclusion survives from
   compositor sources, but with a correction the original missed: on **both KWin and
   sway the TOP layer sits *below* an active fullscreen window**. So the dock must be
   on `OVERLAY`, and putting the reveal sliver on `TOP` — as the first draft proposed
   for deterministic z-order — would make it invisible over fullscreen, silently
   killing reveal exactly where Jetty most advertises it. **[V]**
2. **`exclusive_zone(0)` gives no readback.** It is explicitly
   implementation-dependent and, unlike `visibleFrame`, a client cannot query the
   resulting usable area — yet Jetty does arithmetic against a queryable rect
   (`clampOffset`, `alignAlong`). The workaround is a throwaway four-edge-anchored
   probe surface; centre-plus-offset placement cannot be expressed by anchors alone.
3. **gtk4-layer-shell's failure is not silent.** It emits a `g_warning` naming the
   cause and `gtk_layer_is_supported()` returns FALSE — the "hard startup assertion"
   the research proposed is already built in. Risk downgraded, `LD_PRELOAD` guidance
   retained.
4. **The Jetty Menu keyboard-mode problem was manufactured.** Keyboard mode is
   per-`GtkWindow`, so the menu gets its own surface at `ON_DEMAND` and the dock stays
   `NONE`. The inheritance rule only bites if the menu is implemented as a popup of
   the dock.
5. **UPower: test `Type`, not `IsPresent`**, to decide "no battery"; and
   `!OnBattery` is **not** macOS's `isPlugged` — they diverge on any machine with no
   line-power device exposed, mis-driving `isLowBattery(percent:isPlugged:)`.
6. **The MemAvailable arithmetic was inverted.** Measured: `1 − MemFree/MemTotal`
   reports *higher* usage than `1 − MemAvailable/MemTotal`, so MemFree's hazard is a
   permanently-**alarming** tile on a warm page cache, not a calm one.
7. **ICU timezone data is bundled, not system.** `swift-foundation-icu` carries the
   tz rules, so a distro `tzdata` update will **not** reach Jetty's world clock — the
   opposite hazard from the one assumed.
8. **MPRIS2 is better-postured but not "strictly better".** MediaRemote aggregates
   whatever the system considers now-playing with no per-app opt-in; MPRIS is opt-in
   per player, so a non-implementing player is invisible, and it *adds* a
   multi-player selection problem. Consider `playerctld`'s `ActivePlayer` rather than
   excluding it.
9. **`getloadavg` is the wrong metric for a tile labelled CPU**, and worse on Linux
   than macOS: Linux load counts uninterruptible-sleep tasks, so heavy disk I/O
   inflates it. Use `/proc/stat` deltas if a true busy-% is wanted.
10. **procfs files report `st_size == 0`** — code that pre-sizes a buffer from
    `stat` silently reads nothing. Read to EOF.
11. **KWin already has a compositor-side auto-hide protocol for layer surfaces**
    (`installAutoHideScreenEdgeV1`), which the research missed and which is directly
    relevant to Jetty's central behaviour. Worth a spike.
12. **`DisplayRegistry` gets harder, not deleted**, and **Restore System Dock is
    cross-tier**: `gnome-extensions disable ubuntu-dock@ubuntu.com` writes per-user
    GSettings and is GNOME-only, so the shipped promise needs a per-tier
    implementation, not a port.

Six further domains (app model, toolkit, packaging, hotkeys/power/tray, displays,
trash) were re-verified in a second pass; their corrections are recorded in
[`linux-port-plan.md`](linux-port-plan.md) against the work items they affect.

## Suggested sequence

See [`linux-port-plan.md`](linux-port-plan.md) for the work items. In brief:

1. **`JettyCore` + Linux CI** — extract the pure backbone, run the existing tests on
   Linux. Zero product risk, immediate regression net, macOS strictly better factored.
2. **The tile data seams** — battery, system stats, now-playing, sleep/wake. Fully
   testable, independent of the desktop wall.
3. **`jettyd`** — the headless orchestrator with the app model, trash and hotkeys,
   drivable over D-Bus with `busctl` before any UI exists.
4. **`jetty-shell`** — GTK4 + layer-shell, proving the whole stack on Kubuntu/Sway.
5. **The GNOME Shell extension** — the tier most Ubuntu users need, deliberately last,
   after the daemon and frontend have proven the shared core.
6. **`.deb`** and the update flow.

Estimated shareable code: **~45% of app LOC and ~95% of test LOC**, plus effectively
all of PictKit. The rewrite surface is the ~7,600 LOC of SwiftUI/AppKit views — and
roughly 200 lines of the most intricate pointer-heuristic code get *deleted* rather
than ported.
