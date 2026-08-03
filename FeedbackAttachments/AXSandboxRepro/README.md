# AX Sandbox Window Move Reproduction

This project demonstrates the App Sandbox limitation encountered by a
user-authorized macOS window manager.

It contains two targets that compile the same source code:

- `AXSandboxedRepro`: App Sandbox enabled.
- `AXUnsandboxedRepro`: App Sandbox disabled.

## Requirements

- macOS 12 or later
- Xcode 26 or later
- A development team selected in Signing & Capabilities if Xcode requests one

## Reproduction steps

Run each target separately and repeat these steps:

1. Click **Request Accessibility Access**.
2. Enable the running reproduction app in:
   **System Settings → Privacy & Security → Accessibility**.
3. Return to the reproduction app.
4. Click **Test After 3 Seconds**.
5. Within three seconds, activate another app that has a normal, movable
   window, such as TextEdit.
6. Wait for the reproduction app to return to the foreground.
7. Review the exact Accessibility API results in the log.

The test obtains the other application's focused window, reads its current
`AXPosition` and `AXSize`, then attempts to offset the position by 40 points
and increase the size by 20 points.

Because the two targets use different bundle identifiers, macOS asks for
Accessibility permission separately for each target.

## What to attach to Feedback Assistant

- This complete project as a ZIP archive.
- A screen recording showing the same steps for both targets.
- The result log copied from each target.
- The automatically collected sysdiagnose.
- Any relevant `sandboxd` messages from Console.

## Scope

The sample does not inspect window contents, text, controls, files, or user
data. It only reads and attempts to update the focused window's position and
size.
