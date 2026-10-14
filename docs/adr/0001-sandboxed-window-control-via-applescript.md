---
status: accepted
date: 2026-08-02
---

# Use a user-installed AppleScript for sandboxed window control

PaneDrop is intended for Mac App Store distribution and therefore keeps App
Sandbox enabled. It detects a dragged window with read-only system information,
but moves and resizes that window through a user-installed AppleScript executed
with `NSUserAppleScriptTask` and System Events. This is a deliberate product
architecture, not a compatibility layer or temporary refactor target.

## Decision

Keep the following boundary:

- Swift detects gestures, identifies windows, displays templates, selects a zone,
  and calculates the destination frame.
- Swift does **not** directly write another application's `AXPosition` or `AXSize`.
- A compiled AppleScript installed in the app-specific Application Scripts
  directory performs the final move and resize through System Events.
- PaneDrop remains sandboxed and requires two setup conditions: Accessibility
  access and an up-to-date installed script. The installed script reaches System
  Events through `NSUserAppleScriptTask` without
  `com.apple.security.automation.apple-events` or
  `com.apple.security.temporary-exception.apple-events`.

Do not replace this design with direct Accessibility API writes unless a future,
signed, sandboxed reproduction proves that Apple has made that path reliable and
acceptable for Mac App Store distribution.

## Why direct Accessibility API writes are not used

The obvious implementation is to create an `AXUIElement` for another process and
set `kAXPositionAttribute` and `kAXSizeAttribute` with
`AXUIElementSetAttributeValue`. PaneDrop tested that design rather than rejecting
it on preference alone.

The reproduction project at `FeedbackAttachments/AXSandboxRepro` builds the same
code in two modes:

- `AXSandboxedRepro`: App Sandbox enabled.
- `AXUnsandboxedRepro`: App Sandbox disabled.

It requests Accessibility permission, reads the focused window and its geometry,
checks whether position and size are settable, and attempts the two writes. The
project exists to demonstrate the observed constraint: Accessibility consent does
not make direct cross-application AX writes a dependable window-control mechanism
for PaneDrop while App Sandbox is enabled.

Turning off App Sandbox would make a conventional AX window manager possible, but
would conflict with PaneDrop's Mac App Store distribution goal. Treating the AX
implementation as a straightforward modernization therefore changes a product
constraint; it is not an internal cleanup.

The selected design delegates the privileged operation to System Events through
the macOS-supported user script mechanism. The user explicitly installs the
script and explicitly grants Accessibility and Automation access. PaneDrop keeps
the controlling Apple event narrowly targeted at `com.apple.systemevents`.

## Current implementation

### 1. Detect the drag without controlling the target window

`PaneDrop/App.swift` installs global `NSEvent` monitors for mouse down, mouse drag,
mouse up, and modifier-key changes. These events drive `WindowDragSession` in
`PaneDrop/WindowDrag.swift`.

At mouse-down, `WindowDragSession` uses `CGWindowListCopyWindowInfo` to record the
top-level, layer-zero window under the pointer. The captured `WindowTarget`
contains only the window ID, owner PID, bundle identifier, title, and bounds.

During the drag, the session refreshes the window's bounds and confirms that both
the pointer and the window actually moved before showing the template overlay.
The overlay follows the active display and reports the hovered template zone.

### 2. Calculate the destination in Swift

On mouse-up, `WindowDragSession`:

1. Obtains the currently hovered zone.
2. Refreshes the original target window, with the frontmost window as a fallback.
3. Converts the normalized zone into the target screen's Accessibility coordinate
   space using `zone.accessibilityFrame(on:)`.
4. Passes the target identity, destination position, and destination size to
   `WindowAutomation.setFrame`.

Window selection and layout calculations remain native Swift code. AppleScript is
used only for the final external-window mutation.

### 3. Require a complete setup before window control

`PaneDrop/WindowAutomation.swift` considers the app ready only when:

- `AXIsProcessTrusted()` confirms Accessibility access.
- The installed `.scpt` data exactly matches the bundled script data.

Setup presents these as two user-facing steps. System Events is reached by the
installed script itself; PaneDrop does not ask for a separate Automation Setup
step because signed builds without `com.apple.security.automation.apple-events`
do not get a useful `AEDeterminePermissionToAutomateTarget` signal.

If either item is missing, PaneDrop presents the Setup Assistant instead of trying a
partial or hidden fallback. Keep these as two separate checks because they fail
and recover independently.

### 4. Install the script with explicit user consent

The source script is
`PaneDrop/Scripts/PaneDropWindowControl.applescript`. Xcode compiles it into the
app bundle as `PaneDropWindowControl.scpt`.

Sandboxed `NSUserAppleScriptTask` loads user scripts from the application-specific
Application Scripts directory. PaneDrop resolves that location through
`FileManager.SearchPathDirectory.applicationScriptsDirectory`, resulting in:

```text
~/Library/Application Scripts/<PaneDrop bundle identifier>/PaneDropWindowControl.scpt
```

Installation uses `NSOpenPanel` so the user grants access to the Application
Scripts directory. PaneDrop accepts only that directory or its parent, obtains a
security-scoped resource while copying, creates the bundle-specific child folder
when necessary, and replaces the installed script with the bundled version.

Do not replace this flow with an arbitrary filesystem write, a shell command, or
an `osascript` invocation. Those alternatives change the sandbox and consent
model. Byte-for-byte comparison is also intentional: a release that changes the
script must cause Setup to request installation of the new version.

### 5. Execute a narrow Apple event

`WindowAutomation` creates `NSUserAppleScriptTask` from the installed script and
sends an AppleScript subroutine event named `setWindowFrame`. Arguments are plain
values:

1. Target application bundle identifier.
2. Current window title.
3. Current X and Y position.
4. Target X and Y position.
5. Target width and height.

The task does not send document contents, control contents, file paths, or user
data. The script tells System Events to find the application process by bundle
identifier and then chooses the best matching window.

### 6. Match and move the correct window robustly

The AppleScript cannot rely on a stable Core Graphics window ID through System
Events, so it matches candidates with two signals:

- Exact window title, when the title is non-empty and still available.
- Smallest squared distance from the window's most recently known position.

Title match receives a strong preference, while position remains a fallback for
untitled windows, duplicate titles, and title changes. Swift refreshes the target
immediately before creating these arguments. Removing either part makes it easier
to move the wrong window.

The script moves the window before resizing it. This order is required because
macOS may clamp the requested size to the source display's visible frame if resize
happens before a cross-display move. The initial move itself can also be clamped
while the window still has its original, larger size, so each adjustment pass
resizes the window, reapplies the destination position, and resizes it once more.
This lets full-height zones reach the destination display's top and side edges
instead of preserving the clamp offset.

After moving, the script waits briefly and retries resize up to three times. A
cross-display move can switch Spaces or invalidate the original System Events
window reference, so each failed attempt re-enumerates the process windows and
finds the closest window at the destination before retrying.

## Required configuration

Keep these entries aligned with the implementation:

- App Sandbox remains enabled in the target build settings.
- `com.apple.security.automation.apple-events` is not present. A signed,
  sandboxed Release experiment confirmed that `NSUserAppleScriptTask` reaches
  System Events without it; `AEDeterminePermissionToAutomateTarget` alone is not
  a reliable readiness signal in that configuration.
- `com.apple.security.temporary-exception.apple-events` is not present.
- `com.apple.security.files.user-selected.read-write` supports the explicit
  `NSOpenPanel` installation flow.
- `NSAppleEventsUsageDescription` accurately explains that PaneDrop uses the
  installed script to move and resize the dragged window.
- The script remains a bundled resource and the installed copy remains under the
  app-specific Application Scripts directory.

### Apple Events entitlement experiments

On August 4, 2026, PaneDrop was built and signed with App Sandbox enabled and
`com.apple.security.temporary-exception.apple-events` removed while keeping
`com.apple.security.automation.apple-events`. On a clean TCC path, the first
window operation displayed the standard Automation consent prompt. After
approval, the script proceeded to System Events UI scripting and failed only
because Accessibility had not been granted (`-25211`,
`osascript is not allowed assistive access`). See
`docs/experiments/without-accessibility-and-apple-event-exception.md`.

The same day, a follow-up signed Release build also removed
`com.apple.security.automation.apple-events`. Results:

- The entitlement was absent from the signed app.
- `AEDeterminePermissionToAutomateTarget` returned `-600` for both silent and
  prompting calls.
- With the script installed and Accessibility denied, `NSUserAppleScriptTask`
  still reached System Events and failed only with `-25211`.
- With Accessibility granted, the same script probe succeeded and moved a
  Finder window frame.

This shows the temporary exception and the standard automation entitlement are
both unnecessary for the `NSUserAppleScriptTask` control path. Accessibility
remains required for window mutation. Setup therefore asks only for script
installation and Accessibility access. See
`docs/experiments/without-automation-apple-events-entitlement.md`.

## Review guardrails

Unless the user explicitly asks to revisit this ADR, a code review must treat the
following proposals as architectural regressions:

- Replace `NSUserAppleScriptTask` with direct `AXUIElementSetAttributeValue`.
- Disable App Sandbox to make direct AX writes work.
- Reintroduce `com.apple.security.temporary-exception.apple-events` or
  `com.apple.security.automation.apple-events` without new signed-build evidence
  that the current script path is insufficient.
- Remove Accessibility permission or script installation.
- Collapse the two readiness checks into one optimistic check.
- Add a user-facing Automation Setup step that depends on
  `AEDeterminePermissionToAutomateTarget` without signed evidence that the
  current script path needs it.
- Execute the bundled script directly without installing the user script.
- Use `NSAppleScript`, `osascript`, shell execution, private APIs, or injected code
  as an alternative control path.
- Broaden Apple Event targets beyond System Events without a separately reviewed
  need.
- Identify windows only by title, only by ordering, or only by current position.
- Resize before the initial move, omit the post-resize position correction, or
  remove the retry and re-identification logic without a tested replacement.
- Treat the script as support for another application or a historical data format.
  It is PaneDrop's current window-control component.

Reviews may improve error reporting, concurrency, testability, localization, and
the setup experience as long as the same security boundary and runtime behavior
remain intact.

## Validation required for changes

Changes touching this path should be tested in a signed build with App Sandbox
enabled, not only in an unsandboxed debug helper. At minimum verify:

- A clean macOS account with no existing TCC grants or installed script.
- Script installation by selecting both the Application Scripts parent and the
  app-specific child directory.
- Accessibility denial, later approval, and app relaunch.
- Detection, hover selection, drop, move, and resize in several third-party apps.
- Empty titles, duplicate window titles, and multiple windows from one process.
- Multiple displays with different resolutions, scale factors, and menu-bar/Dock
  arrangements.
- Moving between displays and Spaces, including full-height and full-screen-sized
  target zones.
- A release whose bundled script differs from the installed script.
- Every supported macOS version used for release qualification.

## Reconsidering this decision

This ADR can be superseded only when there is new evidence, such as an Apple API
or entitlement that reliably permits direct window mutation from a Mac App Store
sandbox. Before migration:

1. Update and run `FeedbackAttachments/AXSandboxRepro` with sandbox enabled.
2. Test a signed archive rather than relying on an IDE-only result.
3. Confirm App Store entitlement and review compatibility.
4. Compare permission UX, privacy scope, multi-display behavior, and failure modes.
5. Write a superseding ADR and a migration/rollback plan.

Until all five steps are complete, preserve the current AppleScript architecture.
