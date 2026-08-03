#!/bin/zsh

set -euo pipefail

app_path="${1:-/Applications/PaneDrop.app}"

pkill -x PaneDrop 2>/dev/null || true
open -na "$app_path" --env PANEDROP_UI_REVIEW=1
trap 'pkill -x PaneDrop 2>/dev/null || true' EXIT

sleep 0.6

osascript <<'APPLESCRIPT' >/dev/null
tell application "System Events"
    set frontmost of process "PaneDrop" to true
    delay 0.2
    tell process "PaneDrop"
        perform action "AXPress" of UI element 7 of UI element 1 of UI element 7 of UI element 1 of window 1
    end tell
end tell
APPLESCRIPT

sleep 0.6

click_fixture=$(osascript <<'APPLESCRIPT'
tell application "System Events"
    set frontmost of process "PaneDrop" to true
    delay 0.2
    tell process "PaneDrop"
        set rootGroup to UI element 1 of window 1
        set splitGroup to UI element 1 of rootGroup
        set canvasGroup to UI element 1 of splitGroup
        set inspectorGroup to UI element 3 of splitGroup
        set inspector to UI element 1 of inspectorGroup
        set selector to UI element 1 of UI element 7 of inspector

        perform action "AXPress" of UI element 2 of selector
        delay 0.1
        set beforeValue to value of UI element 10 of inspector
        set canvasPosition to position of canvasGroup
        set canvasSize to size of canvasGroup
        set clickX to (item 1 of canvasPosition) + ((item 1 of canvasSize) * 0.25)
        set clickY to (item 2 of canvasPosition) + ((item 2 of canvasSize) * 0.52)
        return (beforeValue as text) & "," & (clickX as text) & "," & (clickY as text)
    end tell
end tell
APPLESCRIPT
)

IFS=',' read -r before_value click_x click_y <<< "$click_fixture"

xcrun swift -e '
import CoreGraphics
import Foundation

let point = CGPoint(
    x: Double(CommandLine.arguments[1])!,
    y: Double(CommandLine.arguments[2])!
)
let source = CGEventSource(stateID: .hidSystemState)
let down = CGEvent(
    mouseEventSource: source,
    mouseType: .leftMouseDown,
    mouseCursorPosition: point,
    mouseButton: .left
)
let up = CGEvent(
    mouseEventSource: source,
    mouseType: .leftMouseUp,
    mouseCursorPosition: point,
    mouseButton: .left
)
down?.post(tap: .cghidEventTap)
usleep(80_000)
up?.post(tap: .cghidEventTap)
' "$click_x" "$click_y"

sleep 0.2

after_value=$(osascript <<'APPLESCRIPT'
tell application "System Events"
    tell process "PaneDrop"
        set splitGroup to UI element 1 of UI element 1 of window 1
        set inspectorGroup to UI element 3 of splitGroup
        set inspector to UI element 1 of inspectorGroup
        return value of UI element 10 of inspector
    end tell
end tell
APPLESCRIPT
)

result="$before_value,$after_value"

if [[ "$result" != "0.5,0.0" ]]; then
    print -u2 "ZONE_SELECTION_REPRO_FAILED: expected 0.5,0.0; got $result"
    exit 1
fi

print "ZONE_SELECTION_REPRO_PASSED: $result"
