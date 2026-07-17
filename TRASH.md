# Trash Icon & State — Research and Design

How Jetty renders the Trash tile: what actually works on modern macOS (Catalina →
Tahoe 26), what doesn't, and why three earlier attempts failed. Sources are linked
inline. Written 2026-07-17 after the third failed attempt (workspace icon renders as
a plain folder).

## The problem, precisely

Two independent things must be true for a correct Trash tile:

1. **Icon artwork** — a trash-can image, in empty and full variants.
2. **State** — whether the user's Trash currently contains anything.

Every failure so far came from mixing up which of the two broke.

## Failure history

| Attempt | What it did | Why it failed |
|---|---|---|
| Original (`NSImage(named: .trashFullName/.trashEmptyName)`) | Legacy named images gated on a `readdir` probe | The named images **do not resolve on macOS 26** (`NSImage(named:)` returns nil) → tile fell through to the single generic SF `trash` glyph for both states ([upstream commit d5d671e](https://github.com/L-K-M/Jetty/commit/d5d671e)). The *probe* was also broken for most users — see below. |
| d5d671e | SF Symbol fallback (`trash` / `trash.fill`) behind the same probe | Icons fixed, but the probe still reports `.unknown` → empty for anyone whose app can't enumerate `~/.Trash` (TCC — the common case). "Always empty." |
| k3 PR #46 | `NSWorkspace.shared.icon(forFile: ~/.Trash)` | Returns the **generic folder icon**, not the trash can (user-verified on macOS 26). Likely because LaunchServices only hands the special trash-can representation to clients allowed to inspect the folder. Dead end. |

## Research: the icon artwork

| Source | Works? | Notes |
|---|---|---|
| `NSImage(named: NSImage.trashFullName/trashEmptyName)` ("NSTrashFull"/"NSTrashEmpty") | ❌ macOS 26 | Returns nil. Still documented, still returns images on ≤ macOS 15, but gone in 26. |
| `NSWorkspace.icon(forFile: ~/.Trash)` | ❌ | Generic **folder** icon on macOS 26 (verified by the user). |
| SF Symbols `trash` / `trash.fill` | ✅ always | Vector glyphs; visually close, not the "real" can. Good fallback. |
| **`CoreTypes.bundle` resources** | ✅ (≤ Sonoma confirmed, presumed on 26) | `/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/TrashIcon.icns` and `FullTrashIcon.icns` — the exact system artwork ([Ask Different, Apr 2024, Sonoma 14.4](https://apple.stackexchange.com/questions/471872/to-edit-trashicon-icns-using-hex-editor-to-get-access-to-the-dark-icons)). Reading them needs no permission (the system volume is world-readable). If they ever move/vanish → fall back to SF Symbols. |

Note: the `.icns` files also embed dark variants behind a magic chunk
(`FD D9 2F A8`) that `NSImage` does not surface — both appearance modes get the
standard representation, which is acceptable (same as most third-party docks).

## Research: the state

### Enumerating `~/.Trash` requires Full Disk Access

- [Stack Overflow #77815914 (Jan 2024, Sonoma)](https://stackoverflow.com/questions/77815914/macos-sonoma-cron-job-doesnt-have-access-to-trash-even-though-it-has-full-sy):
  `PermissionError: [Errno 1] Operation not permitted: '/Users/me/.Trash'`;
  fixed only by granting Full Disk Access. Cross-posted to the
  [Apple Developer Forums](https://developer.apple.com/forums/thread/745692),
  which points at Quinn "The Eskimo"'s TCC explainer
  ([thread 678819](https://developer.apple.com/forums/thread/678819)).
- Howard Oakley's protected-locations survey
  ([Eclectic Light, Apr 2026, macOS Tahoe 26.4](https://eclecticlight.co/2026/04/07/privacy-protected-folders/))
  documents the mechanism: directory listings and file *reads* in protected
  locations go through `sandboxd` → TCC; writes do not. FDA-class locations (like
  the Trash) fail with `EPERM` and **no consent prompt** — unlike the
  Files & Folders class (`~/Documents`, `~/Downloads`, `~/Desktop`, removable/
  network volumes, iCloud Drive), which *can* prompt when an app first tries.
- Practical consequence: probing per-volume `.Trashes` or network volumes risks
  **spontaneous consent prompts and hangs**; probing `~/.Trash` is prompt-free but
  succeeds only with Full Disk Access. Jetty's core promise is no scary
  permissions, so FDA must not be required — the probe is a *bonus* source, not
  the foundation.

### What does NOT work for state

- `NSWorkspace` / LaunchServices icon state — see above (folder icon).
- `stat()` metadata on `~/.Trash` — `st_nlink` counts subdirectories only and
  `st_size` is not entry-correlated on APFS; nothing in it encodes empty/full.
- Spotlight (`NSMetadataQuery`) — the Trash is excluded from indexing.
- `defaults read com.apple.dock` — trash state is not persisted there.
- Watching alone — a `DispatchSource` vnode watch (Jetty's `TrashMonitor`) tells
  you *something* changed, never *what*; you cannot derive empty/full from events.

### What DOES work: asking Finder

Finder owns the Trash and answers AppleScript: `tell application "Finder" to get
(count of items of trash)`. This is the channel Apple's own ecosystem uses (the
classic `osx-trash` tool and countless scripts work this way). It requires
**Automation consent for Finder** (`kTCCServiceAppleEvents/com.apple.finder`):

- Consent is per-target and sticky once granted — and Jetty's *Empty Trash* power
  command already asks for it, so many users will have granted it.
- Crucially, consent can be **preflighted without prompting**:
  [`AEDeterminePermissionToAutomateTarget(..., askIfNeeded: false)`](https://developer.apple.com/documentation/coreservices/3025784-aedeterminepermissiontoautomatet)
  (macOS 11+; returns `noErr` when granted, `-1744 errAEEventNotPermitted` when
  denied, `-1745` when a prompt would be required). Only when it says *granted*
  may Jetty send passively. A user-initiated "Request…" button may send directly —
  then the OS consent prompt is the expected, comprehensible outcome.

## The design (implemented in this PR)

**Icons** — `TrashIconProvider`: load `TrashIcon.icns` / `FullTrashIcon.icns`
from CoreTypes once, independently per state, each with an SF Symbol fallback
(`trash` / `trash.fill`). Never `NSImage(named:)` (dead on 26), never
`icon(forFile:)` (folder icon).

**State** — three tiers, resolved off the main thread and cached:

1. **Filesystem probe (exact, when permitted).** A single `readdir` of the home
   Trash only. Succeeds with Full Disk Access; costs one syscall; never prompts.
2. **Finder Automation (exact, when consented).** Probe denied → preflight
   Automation consent silently; if granted, `count items of trash` on the shared
   serial AppleScript queue (never the main thread). `-1744`/errors → tier 3.
3. **Honest default.** Neither available → render the **empty** can (the Trash is
   empty most of the time for most users, and a false "full" cried wolf
   constantly in the old code), with a visible fix path: Settings → Permissions
   gets a *Finder Automation* row showing status and a **Request…** button that
   deliberately triggers the OS consent prompt.

Tier selection is a pure, unit-tested function:
`probe .full/.empty → use it; probe .unknown + consent granted → ask Finder;
else → indeterminate (empty rendering).`

**Timeliness** — the resolved state is cached and recomputed on: launch; Trash
vnode watch events (existing 0.3 s coalescing); wake/volume changes; Jetty's own
trash/empty actions; and any dock reveal (throttled to 5 s) so the can is never
staler than the last time the user looked at it. The model only republishes when
the state actually changes — no per-activation rescans (that was the old
main-thread perf bug as well).

## References

- [Ask Different: TrashIcon.icns in CoreTypes (Sonoma 14.4)](https://apple.stackexchange.com/questions/471872/to-edit-trashicon-icns-using-hex-editor-to-get-access-to-the-dark-icons)
- [SO #77815914: ~/.Trash requires Full Disk Access (Sonoma)](https://stackoverflow.com/questions/77815914/macos-sonoma-cron-job-doesnt-have-access-to-trash-even-though-it-has-full-sy)
- [Apple DevForums 745692 (same issue)](https://developer.apple.com/forums/thread/745692) → [eskimo1's TCC explainer 678819](https://developer.apple.com/forums/thread/678819)
- [Eclectic Light: Privacy — protected folders (Tahoe 26.4)](https://eclecticlight.co/2026/04/07/privacy-protected-folders/) and [Files & Folders or Full Disk Access?](https://eclecticlight.co/2026/04/08/privacy-files-folders-or-full-disk-access/)
- [AEDeterminePermissionToAutomateTarget — Apple Documentation](https://developer.apple.com/documentation/coreservices/3025784-aedeterminepermissiontoautomatet)
- [mjtsai on AEDeterminePermissionToAutomateTarget quirks](https://mjtsai.com/blog/2018/08/31/aedeterminepermissiontoautomatetarget-added-but-aepocalyse-still-looms/)
- [NSImage.trashFullName — Apple Documentation](https://developer.apple.com/documentation/appkit/nsimage/trashfullname) (returns nil on macOS 26, verified upstream in d5d671e)
