# PaneDrop Agent Instructions

## Window-control architecture

Before reviewing or changing window detection, window movement, setup permissions,
Apple Events, entitlements, or script installation, read:

- `docs/adr/0001-sandboxed-window-control-via-applescript.md`

PaneDrop's user-installed AppleScript, `NSUserAppleScriptTask`, System Events,
Accessibility permission, Automation permission, and related sandbox entitlements
are a deliberate App Store architecture. They are not legacy compatibility code.

Do not replace this path with direct `AXUIElementSetAttributeValue` calls, remove
script installation or Automation permission, invoke `osascript`, or relax App
Sandbox unless the user explicitly asks to revisit the architecture. A review must
not recommend those changes as cleanup or modernization. Any proposed replacement
must first reproduce successfully in an App-Sandbox-enabled, signed build and must
supersede the ADR with the new evidence and migration plan.
