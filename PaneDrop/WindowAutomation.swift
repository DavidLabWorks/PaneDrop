import AppKit
import ApplicationServices
import Carbon
import Combine

struct SetupStatus: Equatable, Sendable {
    var accessibilityGranted = false
    var scriptInstalled = false
    var automationGranted = false

    var isComplete: Bool {
        accessibilityGranted && scriptInstalled && automationGranted
    }
}

@MainActor
final class WindowAutomation: ObservableObject {
    static let shared = WindowAutomation()

    @Published private(set) var setupStatus = SetupStatus()
    @Published private(set) var installationInProgress = false
    @Published private(set) var automationRequestInProgress = false

    private let scriptName = "PaneDropWindowControl"
    private let systemEventsBundleIdentifier = "com.apple.systemevents"

    private var statusRefreshTask: Task<SetupStatus, Never>?
    private var statusRefreshID: UUID?
    private var readinessHandler: ((Bool) -> Void)?

    private init() {}

    private var scriptsDirectory: URL? {
        guard let bundleIdentifier = Bundle.main.bundleIdentifier else { return nil }

        do {
            let directory = try FileManager.default.url(
                for: .applicationScriptsDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: false
            )

            if directory.lastPathComponent == bundleIdentifier {
                return directory
            }

            return directory.appendingPathComponent(bundleIdentifier, isDirectory: true)
        } catch {
            AppLog.debug("Could not locate Application Scripts directory: \(error)")
            return nil
        }
    }

    private var installedScriptURL: URL? {
        scriptsDirectory?.appendingPathComponent("\(scriptName).scpt")
    }

    private var bundledScriptURL: URL? {
        Bundle.main.url(forResource: scriptName, withExtension: "scpt")
    }

    private nonisolated static func isScriptInstalled(
        installedScriptURL: URL?,
        bundledScriptURL: URL?
    ) -> Bool {
        guard let installedScriptURL,
              let bundledScriptURL,
              let installedData = try? Data(contentsOf: installedScriptURL),
              let bundledData = try? Data(contentsOf: bundledScriptURL)
        else {
            return false
        }

        return installedData == bundledData
    }

    private nonisolated static func determineAutomationPermission(
        askUserIfNeeded: Bool
    ) -> OSStatus {
        let descriptor = NSAppleEventDescriptor(
            bundleIdentifier: "com.apple.systemevents"
        )
        return AEDeterminePermissionToAutomateTarget(
            descriptor.aeDesc,
            typeWildCard,
            typeWildCard,
            askUserIfNeeded
        )
    }

    func configureReadinessHandler(_ handler: @escaping (Bool) -> Void) {
        readinessHandler = handler
    }

    func refreshSetupStatus() {
        Task {
            await updateSetupStatus()
        }
    }

    @discardableResult
    func updateSetupStatus() async -> SetupStatus {
        let task: Task<SetupStatus, Never>
        let refreshID: UUID
        if let statusRefreshTask {
            task = statusRefreshTask
            refreshID = statusRefreshID ?? UUID()
        } else {
            await ensureSystemEventsIsRunning()
            let installedScriptURL = installedScriptURL
            let bundledScriptURL = bundledScriptURL
            refreshID = UUID()
            task = Task.detached(priority: .utility) {
                SetupStatus(
                    accessibilityGranted: AXIsProcessTrusted(),
                    scriptInstalled: Self.isScriptInstalled(
                        installedScriptURL: installedScriptURL,
                        bundledScriptURL: bundledScriptURL
                    ),
                    automationGranted: Self.determineAutomationPermission(
                        askUserIfNeeded: false
                    ) == noErr
                )
            }
            statusRefreshTask = task
            statusRefreshID = refreshID
        }

        let status = await task.value
        if statusRefreshID == refreshID {
            statusRefreshTask = nil
            statusRefreshID = nil
        }
        setupStatus = status
        appState.updateReadiness(status.isComplete)
        readinessHandler?(status.isComplete)

        if status.isComplete {
            SetupAssistantWindowController.shared.completeIfPresented()
        }

        return status
    }

    func prepareIfNeeded() {
        Task {
            let status = await updateSetupStatus()
            if !status.isComplete {
                SetupAssistantWindowController.shared.present()
            }
        }
    }

    func openAccessibilitySettings() {
        if let settingsURL = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        ) {
            NSWorkspace.shared.open(settingsURL)
        }

        refreshAfterSystemPrompt()
    }

    func requestAutomationPermission() {
        guard !automationRequestInProgress else { return }

        automationRequestInProgress = true
        NSApp.activate(ignoringOtherApps: true)

        Task { [weak self] in
            guard let self else { return }
            await self.ensureSystemEventsIsRunning()

            var result = await Task.detached(priority: .userInitiated) {
                Self.determineAutomationPermission(askUserIfNeeded: true)
            }.value

            if result == procNotFound {
                try? await Task.sleep(nanoseconds: 300_000_000)
                result = await Task.detached(priority: .userInitiated) {
                    Self.determineAutomationPermission(askUserIfNeeded: true)
                }.value
            }

            await self.handleAutomationPermissionResult(result)
            self.automationRequestInProgress = false
        }
    }

    private func ensureSystemEventsIsRunning() async {
        guard NSRunningApplication.runningApplications(
            withBundleIdentifier: systemEventsBundleIdentifier
        ).isEmpty else {
            return
        }

        guard let applicationURL = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: systemEventsBundleIdentifier
        ) else {
            return
        }

        await withCheckedContinuation { continuation in
            NSWorkspace.shared.openApplication(
                at: applicationURL,
                configuration: NSWorkspace.OpenConfiguration()
            ) { _, _ in
                continuation.resume()
            }
        }
    }

    private func handleAutomationPermissionResult(_ result: OSStatus) async {
        await updateSetupStatus()

        guard result != noErr else { return }

        if result == errAEEventNotPermitted {
            if let settingsURL = URL(
                string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation"
            ) {
                NSWorkspace.shared.open(settingsURL)
            }
            return
        }

        showError(
            title: L10n.string("error.automation_request_title"),
            message: L10n.string("error.automation_request_detail", result)
        )
    }

    func installScript() {
        guard !installationInProgress else { return }
        guard let bundledScriptURL else {
            showError(
                title: L10n.string("error.script_unavailable_title"),
                message: L10n.string("error.script_unavailable_detail")
            )
            return
        }
        guard let scriptsDirectory, let installedScriptURL else {
            showError(
                title: L10n.string("error.script_directory_title"),
                message: L10n.string("error.script_directory_detail")
            )
            return
        }

        installationInProgress = true

        let fileManager = FileManager.default
        let parentDirectory = scriptsDirectory.deletingLastPathComponent()
        let panel = NSOpenPanel()
        panel.title = L10n.string("script.choose_folder_title")
        panel.message = L10n.string("script.choose_folder_detail")
        panel.prompt = L10n.string("common.choose")
        panel.directoryURL = fileManager.fileExists(atPath: scriptsDirectory.path)
            ? scriptsDirectory
            : parentDirectory
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true

        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let selectedDirectory = panel.url else {
            installationInProgress = false
            return
        }

        let selectedURL = selectedDirectory.standardizedFileURL
        guard selectedURL == scriptsDirectory.standardizedFileURL
                || selectedURL == parentDirectory.standardizedFileURL else {
            finishInstallation(error: WindowAutomationError.wrongInstallationDirectory)
            return
        }

        let accessing = selectedDirectory.startAccessingSecurityScopedResource()
        defer {
            if accessing {
                selectedDirectory.stopAccessingSecurityScopedResource()
            }
        }

        do {
            try replaceScript(from: bundledScriptURL, to: installedScriptURL)
            finishInstallation(error: nil)
        } catch {
            finishInstallation(error: error)
        }
    }

    func setFrame(
        of window: WindowTarget,
        position: CGPoint,
        size: CGSize
    ) {
        guard setupStatus.isComplete else {
            SetupAssistantWindowController.shared.present()
            return
        }

        executeSetFrame(
            target: scriptTarget(for: window),
            position: position,
            size: size
        )
    }

    private func refreshAfterSystemPrompt() {
        Task {
            try? await Task.sleep(nanoseconds: 500_000_000)
            await updateSetupStatus()
        }
    }

    private func replaceScript(from sourceURL: URL, to destinationURL: URL) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(
            at: destinationURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }
        try fileManager.copyItem(at: sourceURL, to: destinationURL)
    }

    private func finishInstallation(error: Error?) {
        installationInProgress = false
        refreshSetupStatus()

        if let error {
            showError(
                title: L10n.string("error.install_script_title"),
                message: error.localizedDescription
            )
        }
    }

    private func scriptTarget(for window: WindowTarget) -> ScriptWindowTarget {
        let currentWindow = WindowDragSession.shared.refreshedTarget(for: window)

        return ScriptWindowTarget(
            bundleIdentifier: currentWindow.bundleIdentifier,
            title: currentWindow.title,
            currentPosition: currentWindow.bounds.origin
        )
    }

    private func executeSetFrame(
        target: ScriptWindowTarget,
        position: CGPoint,
        size: CGSize
    ) {
        guard let installedScriptURL else { return }

        do {
            let task = try NSUserAppleScriptTask(url: installedScriptURL)
            let event = makeSetFrameEvent(
                target: target,
                position: position,
                size: size
            )

            task.execute(withAppleEvent: event) { _, error in
                guard let error else { return }
                Task { @MainActor in
                    AppLog.debug("AppleScript window operation failed: \(error)")
                    let status = await self.updateSetupStatus()

                    if !status.isComplete {
                        SetupAssistantWindowController.shared.present()
                        return
                    }

                    let nsError = error as NSError
                    self.showError(
                        title: L10n.string("error.move_window_title"),
                        message: "\(error.localizedDescription) (error \(nsError.code))"
                    )
                }
            }
        } catch {
            showError(
                title: L10n.string("error.run_script_title"),
                message: error.localizedDescription
            )
        }
    }

    private func makeSetFrameEvent(
        target: ScriptWindowTarget,
        position: CGPoint,
        size: CGSize
    ) -> NSAppleEventDescriptor {
        let event = NSAppleEventDescriptor(
            eventClass: AEEventClass(kASAppleScriptSuite),
            eventID: AEEventID(kASSubroutineEvent),
            targetDescriptor: nil,
            returnID: AEReturnID(kAutoGenerateReturnID),
            transactionID: AETransactionID(kAnyTransactionID)
        )

        event.setParam(
            NSAppleEventDescriptor(string: "setWindowFrame"),
            forKeyword: AEKeyword(keyASSubroutineName)
        )

        let arguments = NSAppleEventDescriptor.list()
        let values: [NSAppleEventDescriptor] = [
            .init(string: target.bundleIdentifier),
            .init(string: target.title),
            .init(int32: Int32(target.currentPosition.x.rounded())),
            .init(int32: Int32(target.currentPosition.y.rounded())),
            .init(int32: Int32(position.x.rounded())),
            .init(int32: Int32(position.y.rounded())),
            .init(int32: Int32(size.width.rounded())),
            .init(int32: Int32(size.height.rounded()))
        ]

        for (index, value) in values.enumerated() {
            arguments.insert(value, at: index + 1)
        }

        event.setParam(arguments, forKeyword: keyDirectObject)
        return event
    }

    private func showError(title: String, message: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: L10n.string("common.ok"))
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}

private struct ScriptWindowTarget {
    let bundleIdentifier: String
    let title: String
    let currentPosition: CGPoint
}

private enum WindowAutomationError: LocalizedError {
    case wrongInstallationDirectory

    var errorDescription: String? {
        switch self {
        case .wrongInstallationDirectory:
            return L10n.string("error.wrong_script_directory")
        }
    }
}
