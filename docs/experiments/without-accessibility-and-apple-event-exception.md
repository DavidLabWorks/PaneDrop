# Experiment: window control without Accessibility preflight or Apple Event exception

## Question

Can the existing `NSUserAppleScriptTask` window-control path work when PaneDrop:

- does not request or preflight Accessibility access;
- does not directly preflight Automation access to System Events; and
- does not include `com.apple.security.temporary-exception.apple-events`?

This experiment does not supersede ADR 0001. Keep these changes isolated until a
signed, sandboxed build succeeds on a clean macOS account.

## Experimental behavior

The setup assistant checks only that the bundled script has been installed in
PaneDrop's Application Scripts directory. The first real window drop is allowed
to execute the script directly. This avoids having PaneDrop's own permission
preflight fail before `NSUserAppleScriptTask` gets a chance to run the script.

`com.apple.security.automation.apple-events` and
`NSAppleEventsUsageDescription` remain in place. Window detection, target
matching, destination calculation, and the AppleScript are unchanged.

## Test procedure

1. Archive or build Release with App Sandbox and code signing enabled.
2. Inspect the signed app's entitlements and confirm that it includes:
   - `com.apple.security.app-sandbox`
   - `com.apple.security.automation.apple-events`
   - no `com.apple.security.temporary-exception.apple-events`
3. Test from a clean macOS user account with no prior PaneDrop TCC grants or
   installed PaneDrop script.
4. Launch PaneDrop and install the window-control component.
5. Confirm that setup completes without opening Accessibility settings.
6. Drag a window into a PaneDrop zone and record:
   - whether an Automation or Accessibility prompt appears;
   - which process or app name the prompt identifies;
   - whether PaneDrop appears in the Accessibility list;
   - whether PaneDrop appears in the Automation list;
   - the full error code and message if the operation fails.
7. If the first attempt prompts for permission, approve it and repeat the same
   window drop without relaunching.
8. Relaunch PaneDrop and repeat the operation.

## Decision rule

The experiment succeeds only if a signed, sandboxed build moves and resizes
third-party windows without requiring PaneDrop to be granted Accessibility
access and without the temporary Apple Event exception entitlement.

If the script fails, or if PaneDrop must be added to Accessibility, the current
window-control feature still has no demonstrated Mac App Store-compatible path.

## Result

Failed on August 4, 2026 with a signed, sandboxed Release build.

The script was installed and `NSUserAppleScriptTask` executed it without the
temporary Apple Event exception. On the first window operation, macOS displayed
the standard Automation consent dialog asking whether PaneDrop could control
System Events. This confirms that `com.apple.security.automation.apple-events`
is sufficient for the consent step on this script path and that the temporary
Apple Event exception is not required.

After Automation access was allowed, the attempted System Events UI operation
failed with error `-25211`:

```text
System Events got an error: “osascript” is not allowed assistive access.
```

This demonstrates that moving and resizing another application's window through
the current System Events script still requires Accessibility approval for the
script execution process. Removing PaneDrop's `AXIsProcessTrusted` preflight and
setup instructions hides the prerequisite but does not remove it.

Do not use this experiment as a Mac App Store submission path. Granting
Accessibility access to `osascript` would retain the same non-accessibility use
that App Review rejected and would add an unsuitable system-tool permission step.
