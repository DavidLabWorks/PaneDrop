# Experiment: NSUserAppleScriptTask without automation.apple-events

## Question

Can PaneDrop's sandboxed `NSUserAppleScriptTask` window-control path work when the
app includes:

- `com.apple.security.app-sandbox`
- no `com.apple.security.automation.apple-events`
- no `com.apple.security.temporary-exception.apple-events`

This mirrors the shipping Pane (`cn.better365.Pane`) entitlement set for Apple
Events. It does not remove Accessibility, script installation, or System Events
usage.

## Experimental behavior

- Remove `com.apple.security.automation.apple-events` from
  `PaneDrop/PaneDrop.entitlements`.
- Keep `NSAppleEventsUsageDescription`.
- Probe with `PANEDROP_AE_EXPERIMENT=1`, which writes
  `~/Library/Containers/<bundle-id>/Data/Library/Logs/PaneDrop-AE-Experiment.log`
  and exits.

## Decision rule

The experiment succeeds only if a signed, sandboxed Release build can execute the
installed window-control script through `NSUserAppleScriptTask` after the user
grants Accessibility. If `AEDeterminePermissionToAutomateTarget` hard-fails while
the script still works, treat that as success that requires Setup to stop relying
on that API alone.

## Result

Succeeded on August 4, 2026 with a signed, sandboxed Release build (`1.0.0` /
`90`).

Observed:

- Signed entitlements contained App Sandbox and user-selected files only. No
  `automation.apple-events` and no temporary Apple Events exception.
- `AEDeterminePermissionToAutomateTarget` returned `-600` for both
  `askUserIfNeeded: false` and `true`.
- With the script installed and Accessibility denied, `NSUserAppleScriptTask`
  reached System Events and failed with `-25211`
  (`osascript is not allowed assistive access`).
- With Accessibility granted, the same script probe succeeded.

Conclusion: the standard `automation.apple-events` entitlement is not required
for this control path. Setup must verify System Events reachability through the
installed script rather than treating `AEDeterminePermissionToAutomateTarget` as
authoritative when that entitlement is absent. Accessibility remains required for
window mutation.

Adopted follow-up: keep the entitlement removed, drop the user-facing Automation
Setup step, and require only script installation plus Accessibility access.
The script retains a `pingSystemEvents` helper for diagnostics and experiments.
