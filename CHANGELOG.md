# Changelog

## Unreleased

- Adopted Livery for panel theming. Stripe decorations no longer show a faint
  hairline between bands, the Memphis and Synthwave corner styles are now
  available, Reduce Transparency turns the dock and menu backgrounds opaque
  (solid and gradient fills included) and they follow the setting live, and the
  gradient angle dial gains keyboard focus, arrow keys and VoiceOver
  adjustment.
- Adopted Keycap for global hotkeys. The dock-toggle and Jetty-Menu shortcuts
  now both fire when set together (the old Carbon handler let one swallow the
  other). Shift-only or system-reserved shortcuts such as ⌘Q, ⌘Space and ⇧⌘4
  are refused while recording, and one saved by an older Jetty is no longer
  registered: Settings says so and asks for a new one. A function key now works
  without a modifier, any Escape cancels recording, and key names follow the
  current keyboard layout.
- Adopted Updraft for update checks. Downloads are verified (HTTPS on a GitHub
  host for the initial URL, every redirect and the final response, an exact size
  check, and SHA-256 when the release provides a digest) and carry the quarantine
  attribute so Gatekeeper evaluates them on first open; a skipped version stays
  skipped when the release is re-tagged; clicking Check for Updates during a
  background check is queued and reported instead of dropped; assets for
  another OS or with an unknown extension are never offered; a failed download
  shows an alert offering the release page instead of opening it silently; the
  release page opened is always this repository's GitHub page; and the daily
  check runs at 90% of the interval so a punctual timer no longer skips a day.
