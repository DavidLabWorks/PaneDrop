import AppKit
import CoreGraphics

struct WindowTarget {
    let windowID: CGWindowID
    let ownerPID: pid_t
    let bundleIdentifier: String
    let title: String
    let bounds: CGRect
}

final class WindowDragSession {
    static let shared = WindowDragSession()

    private let overlay = TemplateOverlayController()
    private var initialWindow: WindowTarget?
    private var initialPointer: CGPoint?
    private var activeDisplay: NSScreen?
    private var panelWasPresented = false

    private init() {}

    func beginGesture(_ event: NSEvent) {
        guard appState.isReady else { return }

        let pointer = event.cgEvent?.location ?? CGEvent(source: nil)?.location
        initialPointer = pointer
        initialWindow = pointer.flatMap(window(at:))
    }

    func updateGesture(_ event: NSEvent) {
        guard appState.isReady,
              let initialWindow,
              let initialPointer,
              let pointer = event.cgEvent?.location ?? CGEvent(source: nil)?.location,
              hypot(
                pointer.x - initialPointer.x,
                pointer.y - initialPointer.y
              ) > 2,
              let liveWindow = refreshed(initialWindow),
              hypot(
                liveWindow.bounds.minX - initialWindow.bounds.minX,
                liveWindow.bounds.minY - initialWindow.bounds.minY
              ) > 1 else {
            return
        }

        guard preferences.allowsPanel(for: event.modifierFlags) else {
            dismissOverlay()
            return
        }

        guard let display = DisplayLocator.shared.preferredDisplay(
            pointerLocation: NSEvent.mouseLocation
        ) else {
            return
        }

        if !panelWasPresented {
            panelWasPresented = true
            activeDisplay = display
            overlay.present(on: display)
        } else if activeDisplay != display {
            activeDisplay = display
            overlay.reposition(to: display)
        }

        overlay.updatePointer(NSEvent.mouseLocation)
    }

    func endGesture(_ event: NSEvent) {
        guard appState.isReady else {
            clearSession()
            return
        }

        let candidate = preferences.allowsPanel(for: event.modifierFlags)
            ? overlay.currentCandidate()
            : nil
        let targetWindow = initialWindow
        dismissOverlay()

        if let candidate,
           let targetWindow = targetWindow.flatMap(refreshed) ?? focusedWindow() {
            templateLibrary.select(named: candidate.templateName)
            let frame = candidate.zone.accessibilityFrame(on: candidate.screen)
            Task { @MainActor in
                WindowAutomation.shared.setFrame(
                    of: targetWindow,
                    position: frame.origin,
                    size: frame.size
                )
            }
        }

        clearSession()
    }

    func modifierFlagsChanged(_ event: NSEvent) {
        guard panelWasPresented,
              !preferences.allowsPanel(for: event.modifierFlags) else {
            return
        }
        dismissOverlay()
    }

    func refreshedTarget(for target: WindowTarget) -> WindowTarget {
        refreshed(target) ?? target
    }

    private func dismissOverlay() {
        overlay.dismiss()
        panelWasPresented = false
        activeDisplay = nil
    }

    private func clearSession() {
        dismissOverlay()
        initialWindow = nil
        initialPointer = nil
    }

    private func refreshed(_ target: WindowTarget) -> WindowTarget? {
        guard let records = CGWindowListCopyWindowInfo(
            .optionIncludingWindow,
            target.windowID
        ) as? [[String: Any]] else {
            return nil
        }
        return records.first.flatMap(parseWindow)
    }

    private func window(at point: CGPoint) -> WindowTarget? {
        guard let records = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else {
            return nil
        }

        return records.lazy.compactMap { record in
            guard self.layer(of: record) == 0,
                  let target = self.parseWindow(record),
                  target.ownerPID != ProcessInfo.processInfo.processIdentifier,
                  target.bounds.contains(point) else {
                return nil
            }
            return target
        }.first
    }

    private func focusedWindow() -> WindowTarget? {
        guard let activePID = NSWorkspace.shared.frontmostApplication?
            .processIdentifier,
              let records = CGWindowListCopyWindowInfo(
                [.optionOnScreenOnly, .excludeDesktopElements],
                kCGNullWindowID
              ) as? [[String: Any]] else {
            return nil
        }

        return records.lazy
            .filter {
                self.layer(of: $0) == 0
                    && ($0[kCGWindowOwnerPID as String] as? NSNumber)?
                        .int32Value == activePID
            }
            .compactMap(parseWindow)
            .first
    }

    private func layer(of record: [String: Any]) -> Int? {
        (record[kCGWindowLayer as String] as? NSNumber)?.intValue
    }

    private func parseWindow(_ record: [String: Any]) -> WindowTarget? {
        guard let windowNumber = record[kCGWindowNumber as String] as? NSNumber,
              let processNumber = record[kCGWindowOwnerPID as String] as? NSNumber,
              let bounds = record[kCGWindowBounds as String] as? [String: CGFloat],
              let application = NSRunningApplication(
                processIdentifier: processNumber.int32Value
              ),
              let bundleIdentifier = application.bundleIdentifier else {
            return nil
        }

        return WindowTarget(
            windowID: windowNumber.uint32Value,
            ownerPID: processNumber.int32Value,
            bundleIdentifier: bundleIdentifier,
            title: record[kCGWindowName as String] as? String ?? "",
            bounds: CGRect(
                x: bounds["X"] ?? 0,
                y: bounds["Y"] ?? 0,
                width: bounds["Width"] ?? 0,
                height: bounds["Height"] ?? 0
            )
        )
    }
}
