import AppKit
import ApplicationServices

@main
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow!
    private var logView: NSTextView!
    private var requestButton: NSButton!
    private var testButton: NSButton!

    private var buildMode: String {
        #if SANDBOXED_REPRO
        return "Sandbox enabled"
        #else
        return "Sandbox disabled"
        #endif
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        installMainMenu()
        createWindow()
        appendLog("Build mode: \(buildMode)")
        appendLog("Bundle ID: \(Bundle.main.bundleIdentifier ?? "unknown")")
        appendLog("Accessibility trusted: \(AXIsProcessTrusted())")
    }

    func applicationShouldTerminateAfterLastWindowClosed(
        _ sender: NSApplication
    ) -> Bool {
        true
    }

    @objc private func requestAccessibilityAccess() {
        let options = [
            kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true
        ] as CFDictionary
        let trusted = AXIsProcessTrustedWithOptions(options)
        appendLog("Accessibility request result: trusted=\(trusted)")
    }

    @objc private func startDelayedTest() {
        testButton.isEnabled = false
        appendLog("")
        appendLog("Switch to another app with a movable window now…")

        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            guard let self else { return }
            self.runWindowMoveTest()
            self.testButton.isEnabled = true
        }
    }

    @objc private func copyLog() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(logView.string, forType: .string)
    }

    private func runWindowMoveTest() {
        guard AXIsProcessTrusted() else {
            appendLog("STOP: Accessibility permission is not granted.")
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        guard let target = NSWorkspace.shared.frontmostApplication else {
            appendLog("STOP: Could not determine the frontmost application.")
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        guard target.processIdentifier != ProcessInfo.processInfo.processIdentifier else {
            appendLog("STOP: The reproduction app is still frontmost.")
            appendLog("Click Test After 3 Seconds, then switch to another app.")
            return
        }

        appendLog("Target: \(target.localizedName ?? "unknown")")
        appendLog("Target PID: \(target.processIdentifier)")

        let application = AXUIElementCreateApplication(target.processIdentifier)
        var windowValue: CFTypeRef?
        var result = AXUIElementCopyAttributeValue(
            application,
            kAXFocusedWindowAttribute as CFString,
            &windowValue
        )
        appendResult("Copy AXFocusedWindow", result)

        if result != .success {
            result = AXUIElementCopyAttributeValue(
                application,
                kAXWindowsAttribute as CFString,
                &windowValue
            )
            appendResult("Copy AXWindows fallback", result)

            if result == .success,
               let windows = windowValue as? [AXUIElement],
               let firstWindow = windows.first {
                windowValue = firstWindow
            }
        }

        guard result == .success,
              let targetWindow = windowValue as! AXUIElement? else {
            appendLog("STOP: No accessible target window was found.")
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        var positionSettable = DarwinBoolean(false)
        result = AXUIElementIsAttributeSettable(
            targetWindow,
            kAXPositionAttribute as CFString,
            &positionSettable
        )
        appendResult(
            "Is AXPosition settable",
            result,
            detail: "\(positionSettable.boolValue)"
        )

        var sizeSettable = DarwinBoolean(false)
        result = AXUIElementIsAttributeSettable(
            targetWindow,
            kAXSizeAttribute as CFString,
            &sizeSettable
        )
        appendResult(
            "Is AXSize settable",
            result,
            detail: "\(sizeSettable.boolValue)"
        )

        guard let position = copyPoint(
            from: targetWindow,
            attribute: kAXPositionAttribute as CFString
        ) else {
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        guard let size = copySize(
            from: targetWindow,
            attribute: kAXSizeAttribute as CFString
        ) else {
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        var newPosition = CGPoint(x: position.x + 40, y: position.y + 40)
        let positionAXValue = AXValueCreate(.cgPoint, &newPosition)!
        result = AXUIElementSetAttributeValue(
            targetWindow,
            kAXPositionAttribute as CFString,
            positionAXValue
        )
        appendResult("Set AXPosition", result)

        var newSize = CGSize(
            width: max(200, size.width + 20),
            height: max(160, size.height + 20)
        )
        let sizeAXValue = AXValueCreate(.cgSize, &newSize)!
        result = AXUIElementSetAttributeValue(
            targetWindow,
            kAXSizeAttribute as CFString,
            sizeAXValue
        )
        appendResult("Set AXSize", result)

        appendLog("Test complete.")
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func copyPoint(
        from element: AXUIElement,
        attribute: CFString
    ) -> CGPoint? {
        var rawValue: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            element,
            attribute,
            &rawValue
        )
        appendResult("Copy AXPosition", result)

        guard result == .success,
              let value = rawValue as! AXValue?,
              AXValueGetType(value) == .cgPoint else {
            return nil
        }

        var point = CGPoint.zero
        guard AXValueGetValue(value, .cgPoint, &point) else { return nil }
        appendLog("Current AXPosition: \(point)")
        return point
    }

    private func copySize(
        from element: AXUIElement,
        attribute: CFString
    ) -> CGSize? {
        var rawValue: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            element,
            attribute,
            &rawValue
        )
        appendResult("Copy AXSize", result)

        guard result == .success,
              let value = rawValue as! AXValue?,
              AXValueGetType(value) == .cgSize else {
            return nil
        }

        var size = CGSize.zero
        guard AXValueGetValue(value, .cgSize, &size) else { return nil }
        appendLog("Current AXSize: \(size)")
        return size
    }

    private func appendResult(
        _ operation: String,
        _ error: AXError,
        detail: String? = nil
    ) {
        var line = "\(operation): \(errorName(error)) (\(error.rawValue))"
        if let detail {
            line += ", value=\(detail)"
        }
        appendLog(line)
    }

    private func errorName(_ error: AXError) -> String {
        switch error {
        case .success: return "success"
        case .failure: return "failure"
        case .illegalArgument: return "illegalArgument"
        case .invalidUIElement: return "invalidUIElement"
        case .invalidUIElementObserver: return "invalidUIElementObserver"
        case .cannotComplete: return "cannotComplete"
        case .attributeUnsupported: return "attributeUnsupported"
        case .actionUnsupported: return "actionUnsupported"
        case .notificationUnsupported: return "notificationUnsupported"
        case .notImplemented: return "notImplemented"
        case .notificationAlreadyRegistered:
            return "notificationAlreadyRegistered"
        case .notificationNotRegistered: return "notificationNotRegistered"
        case .apiDisabled: return "apiDisabled"
        case .noValue: return "noValue"
        case .parameterizedAttributeUnsupported:
            return "parameterizedAttributeUnsupported"
        case .notEnoughPrecision: return "notEnoughPrecision"
        @unknown default: return "unknown"
        }
    }

    private func appendLog(_ message: String) {
        logView.textStorage?.append(
            NSAttributedString(string: message + "\n")
        )
        logView.scrollToEndOfDocument(nil)
    }

    private func createWindow() {
        let contentView = NSView()
        contentView.translatesAutoresizingMaskIntoConstraints = false

        let titleLabel = NSTextField(labelWithString: "AX Window Move Reproduction")
        titleLabel.font = .systemFont(ofSize: 20, weight: .semibold)

        let modeLabel = NSTextField(labelWithString: buildMode)
        modeLabel.font = .systemFont(ofSize: 13, weight: .medium)
        modeLabel.textColor = .secondaryLabelColor

        let instructionLabel = NSTextField(
            wrappingLabelWithString:
                "Grant Accessibility access, then start the delayed test and " +
                "switch to another app with a movable window."
        )
        instructionLabel.textColor = .secondaryLabelColor

        requestButton = NSButton(
            title: "Request Accessibility Access",
            target: self,
            action: #selector(requestAccessibilityAccess)
        )
        requestButton.bezelStyle = .rounded

        testButton = NSButton(
            title: "Test After 3 Seconds",
            target: self,
            action: #selector(startDelayedTest)
        )
        testButton.bezelStyle = .rounded
        testButton.keyEquivalent = "\r"

        let copyButton = NSButton(
            title: "Copy Log",
            target: self,
            action: #selector(copyLog)
        )
        copyButton.bezelStyle = .rounded

        let buttonRow = NSStackView(
            views: [requestButton, testButton, copyButton]
        )
        buttonRow.orientation = .horizontal
        buttonRow.spacing = 8

        logView = NSTextView()
        logView.isEditable = false
        logView.isSelectable = true
        logView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        logView.textContainerInset = NSSize(width: 8, height: 8)

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .bezelBorder
        scrollView.documentView = logView

        let stack = NSStackView(
            views: [
                titleLabel,
                modeLabel,
                instructionLabel,
                buttonRow,
                scrollView
            ]
        )
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(
                equalTo: contentView.leadingAnchor,
                constant: 20
            ),
            stack.trailingAnchor.constraint(
                equalTo: contentView.trailingAnchor,
                constant: -20
            ),
            stack.topAnchor.constraint(
                equalTo: contentView.topAnchor,
                constant: 20
            ),
            stack.bottomAnchor.constraint(
                equalTo: contentView.bottomAnchor,
                constant: -20
            ),
            scrollView.widthAnchor.constraint(equalTo: stack.widthAnchor),
            scrollView.heightAnchor.constraint(greaterThanOrEqualToConstant: 260),
            instructionLabel.widthAnchor.constraint(equalTo: stack.widthAnchor)
        ])

        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 660, height: 440),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "AX Sandbox Reproduction"
        window.contentView = contentView
        window.center()
        window.makeKeyAndOrderFront(nil)
        window.setContentSize(NSSize(width: 660, height: 440))
        window.minSize = NSSize(width: 580, height: 380)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func installMainMenu() {
        let mainMenu = NSMenu()
        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)

        let appMenu = NSMenu()
        let quitItem = NSMenuItem(
            title: "Quit \(ProcessInfo.processInfo.processName)",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        appMenu.addItem(quitItem)
        appMenuItem.submenu = appMenu
        NSApp.mainMenu = mainMenu
    }
}
