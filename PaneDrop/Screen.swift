import AppKit

final class DisplayLocator {
    static let shared = DisplayLocator()

    private var lastDisplayIdentifier: NSNumber?

    private init() {}

    func display(containing point: CGPoint) -> NSScreen? {
        guard let screen = NSScreen.screens.first(where: {
            NSMouseInRect(point, $0.frame, false)
        }) else {
            return nil
        }

        lastDisplayIdentifier = identifier(of: screen)
        return screen
    }

    func preferredDisplay(pointerLocation: CGPoint = NSEvent.mouseLocation) -> NSScreen? {
        if let screen = display(containing: pointerLocation) {
            return screen
        }

        guard let lastDisplayIdentifier else {
            return NSScreen.main ?? NSScreen.screens.first
        }

        return NSScreen.screens.first {
            identifier(of: $0) == lastDisplayIdentifier
        } ?? NSScreen.main ?? NSScreen.screens.first
    }

    func accessibilityTop(for screen: NSScreen) -> CGFloat {
        let primaryTop = NSScreen.screens.first?.frame.maxY ?? screen.frame.maxY
        return primaryTop - screen.frame.maxY
    }

    private func identifier(of screen: NSScreen) -> NSNumber? {
        screen.deviceDescription[
            NSDeviceDescriptionKey("NSScreenNumber")
        ] as? NSNumber
    }
}
