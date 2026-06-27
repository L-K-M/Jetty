# Jetty

A fast, native, **auto-hiding dock for macOS Tahoe** — a stand-in for the system Dock
with the things the real Dock still won't give you: **position it anywhere**, **style
it deeply**, and **do more with it**.

**Latest release:** v<!-- version -->0.1.0<!-- /version --> · [Download](https://github.com/L-K-M/Jetty/releases/latest)

> [!IMPORTANT]
> LLM Disclosure: Jetty was built with substantial help from large language models —
> primarily Anthropic's Claude, via Claude Code. Much of the code arrived through
> AI-authored commits and `claude/*` branches, with agent guidance kept in
> [`AGENTS.md`](AGENTS.md).

Jetty hides Apple's Dock and floats its own in its place — but only when you want it.
It's the third app in the L-K-M family alongside **[Zap](https://github.com/L-K-M/Zap)**
(a ⌘-Tab switcher) and **[MacDring](https://github.com/L-K-M/MacDring)** (edge-tab
launcher).

## Features

- **Position it anywhere.** Any **edge** (bottom / top / left / right) × any
  **alignment** (leading / center / trailing) × a fine offset and an edge inset, **per
  display**. Want a **bottom-right** dock, or a floating island top-center? Two clicks.
  The real Dock gives you three positions, always centered; Jetty doesn't.
- **Native Liquid Glass, your way.** Real macOS 26 Liquid Glass (regular / clear /
  tinted), or solid / gradient — with tunable tint, icon size, tile spacing, corner
  radius, hover **magnification**, and running-indicator style. Save and share your
  look as a **preset** (`.json` import/export), or start from a built-in theme.
- **Auto-hidden, overlaps on reveal.** Jetty stays out of the way and slides in over
  whatever's on screen when you push the pointer to its edge (or hit a hotkey). No
  reserved strip, no windows getting shoved around — and **no permissions** for the
  core dock.
- **Pinned + running apps**, with live running indicators, one-click launch/activate,
  drag-a-file-onto-an-app to open it there, drag-to-pin and reorder, and a right-click
  menu (Show / Hide / Quit / Keep in Dock / Show in Finder).
- **A date/time tile** right in the dock — 12/24-hour, seconds, weekday, date.
- **The Jetty Menu** — a Windows-Start-style launcher with **instant app search**
  (type to filter, ↑/↓, ⏎) and **power commands**: Sleep, Lock Screen, Log Out,
  Restart, Shut Down, Empty Trash.
- **Trash tile** — click to open, drop files to delete.
- **Multi-monitor** aware, with placements that **restore after restart**, resolution
  change, and reconnection (keyed to a stable display identity).
- **Menu-bar agent** (no Dock icon of its own), launch-at-login via `SMAppService`,
  and an in-app GitHub updater.

## How it works (and what it can't do)

macOS doesn't let *any* app truly replace or remove the Dock — it's a protected system
process that also runs Mission Control and window minimizing. So Jetty does what every
reliable third-party dock does: it **hides** Apple's Dock (auto-hide + a long reveal
delay) and runs its own **alongside** it, using only public APIs (no SIP changes, no
code injection). One click in **Settings → General → Restore System Dock** puts the
real Dock back. See [`PLAN.md`](PLAN.md) for the full feasibility analysis.

Because Jetty floats over content instead of reserving space, maximized windows aren't
pushed aside — which is exactly why it auto-hides and needs no Accessibility permission
to run.

## Build & Run

Requires **Xcode 26** (for Liquid Glass) and **macOS 13+** (Liquid Glass renders on
macOS 26; older systems get a blurred fallback).

```bash
# Build
xcodebuild -project Jetty.xcodeproj -scheme Jetty -configuration Debug build

# Release build
xcodebuild -project Jetty.xcodeproj -scheme Jetty -configuration Release build

# Run unit tests
xcodebuild -project Jetty.xcodeproj -scheme Jetty -destination 'platform=macOS' test
```

`scripts/build.sh` does a convenient incremental Release build via the shared
`lkm-build` engine (`scripts/build.sh --clean` for a clean rebuild).

## Usage

1. Launch Jetty — it appears as a dock glyph in the menu bar and (with your consent)
   hides the system Dock.
2. Push the pointer to the bottom of the screen to reveal the dock, or open
   **Jetty Settings…** from the menu-bar item to choose an edge, alignment, and look.
3. Open the **Jetty Menu** from its dock tile, the menu-bar item, or ⌃⌥⌘Space to
   search apps and access power commands.

## Permissions

The **core dock needs none.** The Jetty Menu's power commands ask for **Automation**
the first time (to tell System Events to sleep/restart/etc.). Optional, *coming-soon*
window-preview / window-management features will ask for **Screen Recording** /
**Accessibility** — and Jetty works fully without them.

## Distribution

Developer ID-signed + notarized, non-sandboxed (no Mac App Store — the sandbox can't
grant the access the window features need). CI publishes an **unsigned** build for each
tag; Gatekeeper will warn on first launch (right-click → Open, or
`xattr -dr com.apple.quarantine /Applications/Jetty.app`).
