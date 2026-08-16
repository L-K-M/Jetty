# Security Policy

## Supported versions

Security fixes are provided for the latest released version of Jetty.

## Reporting a vulnerability

Please use GitHub's private vulnerability reporting feature for this repository. Do not
include passwords, private keys, or other secrets in a report. If private reporting is
unavailable, open an issue that contains no sensitive details and request a private
contact channel.

## Security boundary

Jetty's security boundary is deliberately layered. The core dock is permission-free by
design; every capability beyond it is opt-in behind its own system gate. Power commands
and the Dark Mode toggle send fixed AppleScript strings — no user input is ever
interpolated into a script — to System Events and Finder under macOS's per-target
Automation prompt. Raising or minimizing a specific window requires Accessibility; live
window thumbnails require Screen Recording; both belong to the opt-in hover-preview
feature and Jetty works fully without either. The now-playing tile reads the current
track locally via the MediaRemote framework and fails closed if that framework is
unavailable.

Everything Jetty receives from the network — GitHub release metadata for update checks,
Open-Meteo weather readings, Frankfurter currency rates — is treated as untrusted JSON
that drives only version comparison and tile rendering. Updates are never installed
automatically: the selected release asset is validated against its expected size, saved
to `~/Downloads`, and revealed in Finder for the user to open, with Gatekeeper applying
as usual. The app is not sandboxed (the App Sandbox cannot grant the Accessibility
access the window features need) and carries a single Hardened Runtime entitlement,
`com.apple.security.automation.apple-events`.
