import AppKit
import SwiftUI

final class ApplicationState: ObservableObject {
    @Published private(set) var isReady = false

    func updateReadiness(_ value: Bool) {
        isReady = value
    }
}

let appState = ApplicationState()

private final class DragEventMonitor {
    private var registrations: [Any] = []

    var isRunning: Bool {
        !registrations.isEmpty
    }

    func start() {
        guard registrations.isEmpty else { return }

        register(.leftMouseDown) {
            WindowDragSession.shared.beginGesture($0)
        }
        register(.leftMouseDragged) {
            WindowDragSession.shared.updateGesture($0)
        }
        register(.leftMouseUp) {
            WindowDragSession.shared.endGesture($0)
        }
        register(.flagsChanged) {
            WindowDragSession.shared.modifierFlagsChanged($0)
        }
    }

    func stop() {
        registrations.forEach(NSEvent.removeMonitor)
        registrations.removeAll()
    }

    private func register(
        _ mask: NSEvent.EventTypeMask,
        handler: @escaping (NSEvent) -> Void
    ) {
        guard let registration = NSEvent.addGlobalMonitorForEvents(
            matching: mask,
            handler: handler
        ) else {
            AppLog.debug("Could not register global event monitor for \(mask)")
            return
        }
        registrations.append(registration)
    }
}

final class AppShell: NSObject, NSPopoverDelegate {
    static let shared = AppShell()

    private var statusItem: NSStatusItem?
    private let settingsPopover = NSPopover()
    private var outsideClickMonitor: Any?
    private var modalInteractionDepth = 0

    var isSettingsVisible: Bool {
        settingsPopover.isShown
    }

    private override init() {
        super.init()
    }

    func installMenuBarItem() {
        guard statusItem == nil else { return }

        let item = NSStatusBar.system.statusItem(
            withLength: NSStatusItem.variableLength
        )
        let button = item.button
        let icon = NSImage(named: "MenuBarIcon")
            ?? NSImage(
                systemSymbolName: "rectangle.3.group",
                accessibilityDescription: "PaneDrop"
            )
        icon?.size = NSSize(width: 18, height: 18)
        icon?.isTemplate = true
        button?.image = icon
        button?.target = self
        button?.action = #selector(toggleSettings)
        statusItem = item

        settingsPopover.animates = true
        settingsPopover.behavior = .transient
        settingsPopover.delegate = self
        settingsPopover.contentViewController = NSHostingController(
            rootView: MenuBarSettingsRoot()
        )
    }

    func presentSettings() {
        guard let button = statusItem?.button else { return }

        NSApp.setActivationPolicy(.accessory)
        settingsPopover.show(
            relativeTo: button.bounds,
            of: button,
            preferredEdge: .minY
        )
        NSApp.activate(ignoringOtherApps: true)
        settingsPopover.contentViewController?.view.window?.makeKey()
        beginOutsideClickMonitoring()
    }

    func dismissSettings() {
        endOutsideClickMonitoring()
        settingsPopover.performClose(nil)
    }

    @MainActor
    func performModalInteraction(
        _ operation: @escaping () -> Void
    ) {
        let shouldRestoreSettings = settingsPopover.isShown
        modalInteractionDepth += 1
        endOutsideClickMonitoring()
        NSApp.setActivationPolicy(.accessory)
        NSApp.activate(ignoringOtherApps: true)

        if shouldRestoreSettings {
            let previousAnimationSetting = settingsPopover.animates
            settingsPopover.animates = false
            settingsPopover.performClose(nil)
            settingsPopover.animates = previousAnimationSetting
        }

        DispatchQueue.main.async {
            NSApp.setActivationPolicy(.accessory)
            NSApp.activate(ignoringOtherApps: true)
            defer {
                self.modalInteractionDepth -= 1
                DispatchQueue.main.async {
                    if shouldRestoreSettings {
                        self.presentSettings()
                    } else {
                        self.deactivateIfPossible()
                    }
                }
            }

            operation()
        }
    }

    @objc private func toggleSettings() {
        Task { @MainActor in
            let setup = await WindowAutomation.shared.updateSetupStatus()

            if !setup.isComplete {
                dismissSettings()
                SetupAssistantWindowController.shared.present()
            } else if isSettingsVisible {
                dismissSettings()
            } else {
                SetupAssistantWindowController.shared.dismissIfPresented()
                presentSettings()
            }
        }
    }

    func popoverWillClose(_ notification: Notification) {
        endOutsideClickMonitoring()
        templateLibrary.flushPendingSelection()

        Task { @MainActor in
            deactivateIfPossible()
        }
    }

    func tearDown() {
        endOutsideClickMonitoring()
        if let statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
        }
        statusItem = nil
    }

    private func beginOutsideClickMonitoring() {
        endOutsideClickMonitoring()
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            DispatchQueue.main.async {
                guard self?.isSettingsVisible == true else { return }
                self?.dismissSettings()
            }
        }
    }

    private func endOutsideClickMonitoring() {
        guard let outsideClickMonitor else { return }
        NSEvent.removeMonitor(outsideClickMonitor)
        self.outsideClickMonitor = nil
    }

    @MainActor
    private func deactivateIfPossible() {
        guard modalInteractionDepth == 0,
              !settingsPopover.isShown,
              !ZoneEditorWindowController.shared.isPresented,
              !SetupAssistantWindowController.shared.isPresented else {
            return
        }
        NSApp.setActivationPolicy(.prohibited)
    }
}

private enum RestartCoordinator {
    static var requested = false

    static func request() {
        requested = true
        NSApp.terminate(nil)
    }

    static func launchReplacementIfNeeded() {
        guard requested else { return }

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = [
            "-c",
            "sleep 1; exec /usr/bin/open -n \"$1\"",
            "panedrop-relaunch",
            Bundle.main.bundlePath
        ]

        do {
            try task.run()
        } catch {
            AppLog.debug("Unable to relaunch PaneDrop: \(error)")
        }
    }
}

func requestAppRestart() {
    RestartCoordinator.request()
}

@main
struct PaneDropApplication: App {
    @NSApplicationDelegateAdaptor(PaneDropAppDelegate.self)
    private var appDelegate

    var body: some Scene {
        Settings {}
    }
}

final class PaneDropAppDelegate: NSObject, NSApplicationDelegate {
    private let dragMonitor = DragEventMonitor()
    private var reviewWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        #if DEBUG
        if ProcessInfo.processInfo.environment["PANEDROP_SELF_TEST"] == "1" {
            do {
                try PaneDropSelfTest.run()
                print("PANEDROP_SELF_TEST_PASSED")
                NSApp.terminate(nil)
            } catch {
                fatalError("PANEDROP_SELF_TEST_FAILED: \(error.localizedDescription)")
            }
            return
        }
        #endif

        if ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" {
            appState.updateReadiness(true)
            return
        }

        if ProcessInfo.processInfo.environment["PANEDROP_UI_REVIEW"] == "1" {
            presentReviewWindow()
            return
        }

        guard enforceSingleInstance() else { return }

        NSApp.setActivationPolicy(.prohibited)
        AppShell.shared.installMenuBarItem()

        SetupAssistantWindowController.shared.configure { [weak self] in
            self?.finishSetup()
        }
        WindowAutomation.shared.configureReadinessHandler { [weak self] ready in
            ready ? self?.dragMonitor.start() : self?.dragMonitor.stop()
        }

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 350_000_000)
            WindowAutomation.shared.prepareIfNeeded()
        }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        SetupAssistantWindowController.shared.refreshIfPresented()
    }

    func applicationShouldTerminate(
        _ sender: NSApplication
    ) -> NSApplication.TerminateReply {
        let mayClose = ZoneEditorWindowController.shared
            .confirmApplicationTermination()
        if !mayClose {
            RestartCoordinator.requested = false
        }
        return mayClose ? .terminateNow : .terminateCancel
    }

    func applicationWillTerminate(_ notification: Notification) {
        dragMonitor.stop()
        templateLibrary.flushPendingSelection()
        AppShell.shared.tearDown()
        RestartCoordinator.launchReplacementIfNeeded()
    }

    @MainActor
    private func finishSetup() {
        dragMonitor.start()
        SetupAssistantWindowController.shared.dismissIfPresented()
        AppShell.shared.presentSettings()
    }

    private func enforceSingleInstance() -> Bool {
        guard let identifier = Bundle.main.bundleIdentifier else {
            return true
        }

        let otherInstances = NSRunningApplication
            .runningApplications(withBundleIdentifier: identifier)
            .filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
        guard !otherInstances.isEmpty else { return true }

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = L10n.string("single_instance.title")
        alert.informativeText = L10n.string("single_instance.detail")
        alert.addButton(withTitle: L10n.string("common.ok"))
        NSApp.setActivationPolicy(.accessory)
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
        NSApp.terminate(nil)
        return false
    }

    private func presentReviewWindow() {
        appState.updateReadiness(true)
        NSApp.setActivationPolicy(.regular)

        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 472, height: 700),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "PaneDrop UI Review"
        window.contentView = NSHostingView(rootView: SettingsView().padding(16))
        window.center()
        window.makeKeyAndOrderFront(nil)
        reviewWindow = window
        NSApp.activate(ignoringOtherApps: true)
    }
}
