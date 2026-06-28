# awesome.md — Jetty review backlog (status)

The review that started this file has been worked all the way through. Everything
actionable shipped to `main`: the bugs (BUG-4…BUG-10), the general issues
(GI-1, GI-2, GI-4, GI-5), the full missing-features list (MF-1…MF-7), and the
in-scope novel ideas (ND-1…ND-5, ND-8, ND-9) — including the now-playing info
tile (ND-3) via an isolated, opt-in MediaRemote bridge. Only the items below are
still outstanding.

## Still open

### GI-3 — Localization
No `Localizable.strings` / `String(localized:)`; all user-facing strings are
hardcoded English. Fine for now, but worth a pass before any localization push.
(The clock already localizes via `setLocalizedDateFormatFromTemplate`, which is the
pattern to follow.)

## Decided to be out of scope — do not implement

- **ND-6 — ⌘1…⌘9 quick-launch.** Launch the Nth pinned app with a chord.
- **ND-7 — Shareable theme deep links & a gallery.** A `jetty://theme/<base64>`
  link + a built-in gallery (presets already import/export as JSON).
- **ND-10 — Auto-edge / "throw" the dock.** Reveal at whichever edge the pointer
  pushes to, or drag-and-throw the dock to snap it to the nearest edge + alignment.
