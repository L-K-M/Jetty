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
