# Jetty Privacy Policy

Effective August 16, 2026

Jetty does not operate an account or analytics service, and it does not sell personal
data. It contains no advertising, telemetry, or tracking. Everything Jetty stores stays
on the Mac: the dock layout and pinned items live in Jetty's Application Support
folder, and preferences — position, shortcuts, renamed items, custom icons — live in
Jetty's application preferences. None of it is uploaded anywhere.

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

Permissions map one-to-one to optional features: **Automation** (System Events /
Finder) powers the power commands and the Dark Mode toggle; **Accessibility** enables
click-to-raise / minimize in the opt-in hover window previews plus Not Responding
badges; **Screen Recording** enables live window thumbnails there. The now-playing tile
reads the current track locally via the system's MediaRemote framework and never
transmits it. The core dock needs no permissions at all.

Removing Jetty and its application data removes the stored dock layout and preferences.
Questions or security reports can be submitted through the project's GitHub repository.
