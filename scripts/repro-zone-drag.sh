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

drag_fixture=$(osascript <<'APPLESCRIPT'
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
        set startX to (item 1 of canvasPosition) + ((item 1 of canvasSize) * 0.75)
        set startY to (item 2 of canvasPosition) + ((item 2 of canvasSize) * 0.52)
        set endX to startX - 60
        return (beforeValue as text) & "," & (startX as text) & "," & (startY as text) & "," & (endX as text)
    end tell
end tell
APPLESCRIPT
)

IFS=',' read -r before_value start_x start_y end_x <<< "$drag_fixture"

xcrun swift -e '
import CoreGraphics
import Foundation

let start = CGPoint(
    x: Double(CommandLine.arguments[1])!,
    y: Double(CommandLine.arguments[2])!
)
let end = CGPoint(
    x: Double(CommandLine.arguments[3])!,
    y: Double(CommandLine.arguments[2])!
)
let source = CGEventSource(stateID: .hidSystemState)

func post(_ type: CGEventType, at point: CGPoint) {
    CGEvent(
        mouseEventSource: source,
        mouseType: type,
        mouseCursorPosition: point,
        mouseButton: .left
    )?.post(tap: .cghidEventTap)
}

post(.mouseMoved, at: start)
usleep(40_000)
post(.leftMouseDown, at: start)
for step in 1...6 {
    let progress = CGFloat(step) / 6
    let point = CGPoint(
        x: start.x + (end.x - start.x) * progress,
        y: start.y
    )
    usleep(30_000)
    post(.leftMouseDragged, at: point)
}
usleep(40_000)
post(.leftMouseUp, at: end)
' "$start_x" "$start_y" "$end_x"

sleep 0.2

after_value=$(osascript <<'APPLESCRIPT'
tell application "System Events"
    tell process "PaneDrop"
        set splitGroup to UI element 1 of UI element 1 of window 1
        set inspector to UI element 1 of UI element 3 of splitGroup
        return value of UI element 10 of inspector
    end tell
end tell
APPLESCRIPT
)

if ! awk -v before="$before_value" -v after="$after_value" 'BEGIN { exit !(after < before) }'; then
    print -u2 "ZONE_DRAG_REPRO_FAILED: expected X to decrease; got $before_value,$after_value"
    exit 1
fi

print "ZONE_DRAG_REPRO_PASSED: $before_value,$after_value"
