# Jetty Privacy Policy

Effective August 16, 2026

Jetty does not operate an account or analytics service, and it does not sell personal
data. It contains no advertising, telemetry, or tracking. Everything Jetty stores stays
on the Mac: the dock layout and pinned items — including renamed items and custom
icons — live in Jetty's Application Support folder, and preferences such as position
and shortcuts live in Jetty's application preferences. None of it is uploaded
anywhere.

Jetty makes network requests in exactly three cases, each with a fixed purpose:

- **Update checks.** Jetty asks GitHub's public releases API whether a newer version
  exists — on launch and about once a day while automatic checks are enabled (they can
  be turned off in Settings), or when the user chooses Check for Updates. The request
  contains no system profile or identifiers; the app identifies itself only by its
  bundle identifier. Choosing **Download** saves the release file from GitHub to
  `~/Downloads` and reveals it in Finder — Jetty never installs updates automatically.
- **Weather tile.** Only when the user adds the tile and enters coordinates, Jetty
  fetches current conditions from Open-Meteo (no key, no account) about every fifteen
  minutes while shown. Jetty has no Location permission and never determines the Mac's
  location — the typed coordinates are the only location data sent.
- **Currency conversion.** The Jetty Menu fetches a generic USD-based rate table from
  Frankfurter (ECB data, no key) at most every six hours. The amounts and currencies
  the user types never leave the Mac; conversion happens locally against the cache.

Like any network request, these services receive ordinary connection metadata such as
the source IP address. The Jetty Menu's web-search command opens the default browser
with the typed query — that request is made by the browser, under its own privacy
policy, and only when the user invokes it.

Permissions map to optional features: **Automation** (System Events / Finder) powers
the power commands, the Dark Mode toggle, and — once granted — the passive Trash-count
query behind the Trash tile's fullness state; **Accessibility** enables
click-to-raise / minimize in the hover window previews (the permission-free
window-names mode is on by default; the grant itself is optional) plus Not Responding
badges; **Screen Recording** enables the opt-in live window thumbnails there. The now-playing tile
reads the current track locally via the system's MediaRemote framework and never
transmits it. The core dock needs no permissions at all.

Removing Jetty and its application data removes the stored dock layout and preferences.
Questions can be asked through the project's GitHub repository; please report security
vulnerabilities privately, as described in [SECURITY.md](SECURITY.md).
