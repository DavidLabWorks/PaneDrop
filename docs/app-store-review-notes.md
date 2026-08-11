# App Store Review Notes

## Review notes

PaneDrop is a user-initiated window arrangement utility. It observes the window
the user is actively dragging, displays the selected local layout, and moves and
resizes that window only when the user releases it over a layout zone.

PaneDrop does not read, record, store, or transmit window contents. Window
identity and geometry are processed locally and only for the active drag.

The app remains App Sandbox enabled. It does not include
`com.apple.security.temporary-exception.apple-events` or
`com.apple.security.automation.apple-events`. Window control uses the public
`NSUserAppleScriptTask` API with a user-installed script.

The final window operation is performed by that script in PaneDrop's
application-specific Application Scripts directory. The script targets only
System Events and only moves and resizes the selected window. Accessibility
permission is required for that System Events UI scripting operation.

## Review setup

1. Launch PaneDrop.
2. Select **Install Window Control Component** and choose the Application Scripts
   directory requested by the app.
3. Open **Accessibility** from PaneDrop Setup and add PaneDrop to the list.
4. Drag a standard application window. Move the pointer over a PaneDrop layout
   zone and release it to move and resize the window.

## Support

Support URL:
https://davidlabworks.github.io/panedrop-privacy/support/

Support email:
honeypotdang@gmail.com
