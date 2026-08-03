import AppKit
import SwiftUI

private struct DraggableApplicationBadge: View {
    private let appIcon = NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath)

    var body: some View {
        HStack(spacing: 8) {
            Image(nsImage: appIcon)
                .resizable()
                .frame(width: 24, height: 24)

            Text(L10n.string("setup.drag_accessibility"))
                .font(.caption.weight(.medium))

            Image(systemName: "arrow.right")
                .font(.caption2.weight(.semibold))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(Color.accentColor.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .stroke(
                    Color.accentColor.opacity(0.55),
                    style: StrokeStyle(lineWidth: 1, dash: [4, 3])
                )
        )
        .contentShape(Rectangle())
        .onDrag {
            NSItemProvider(object: Bundle.main.bundleURL as NSURL)
        }
        .help(L10n.string("setup.drag_accessibility_help"))
        .accessibilityLabel(L10n.string("setup.drag_accessibility_help"))
    }
}

private struct SetupStatusMark: View {
    let step: Int
    let isComplete: Bool

    var body: some View {
        ZStack {
            Circle()
                .fill(isComplete ? Color.green : Color.accentColor.opacity(0.12))

            if isComplete {
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.white)
            } else {
                Text("\(step)")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.accentColor)
            }
        }
        .frame(width: 26, height: 26)
        .accessibilityHidden(true)
    }
}

private struct SetupRequirementRow: View {
    let step: Int
    let title: String
    let detail: String
    let isComplete: Bool
    let actionTitle: String
    let isActionDisabled: Bool
    var showsAppDragSource = false
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                SetupStatusMark(step: step, isComplete: isComplete)

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.body.weight(.medium))

                    Text(detail)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 16)

                if isComplete {
                    Label(
                        L10n.string("common.ready"),
                        systemImage: "checkmark"
                    )
                    .font(.caption.weight(.medium))
                    .foregroundColor(.green)
                } else {
                    Button(actionTitle, action: action)
                        .disabled(isActionDisabled)
                        .controlSize(.regular)
                }
            }

            if showsAppDragSource && !isComplete {
                DraggableApplicationBadge()
                    .padding(.leading, 38)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }
}

struct SetupAssistantView: View {
    @ObservedObject var automation: WindowAutomation
    @ObservedObject var settings = preferences
    let close: () -> Void

    private let appIcon = NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath)

    private var completedRequirementCount: Int {
        [
            automation.setupStatus.accessibilityGranted,
            automation.setupStatus.scriptInstalled,
            automation.setupStatus.automationGranted
        ].filter { $0 }.count
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Image(nsImage: appIcon)
                    .resizable()
                    .frame(width: 48, height: 48)

                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.string("setup.title"))
                        .font(.title2.weight(.semibold))

                    Text(L10n.string("setup.subtitle"))
                        .font(.body)
                        .foregroundColor(.secondary)
                }

                Spacer(minLength: 24)

                VStack(alignment: .trailing, spacing: 7) {
                    Text(
                        L10n.string(
                            "setup.progress",
                            completedRequirementCount
                        )
                    )
                    .font(.caption)
                    .foregroundColor(.secondary)

                    ProgressView(
                        value: Double(completedRequirementCount),
                        total: 3
                    )
                    .controlSize(.small)
                    .frame(width: 112)
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)

            Divider()

            VStack(spacing: 16) {
                GroupBox {
                    SetupRequirementRow(
                        step: 1,
                        title: L10n.string("setup.script"),
                        detail: L10n.string("setup.script_detail"),
                        isComplete: automation.setupStatus.scriptInstalled,
                        actionTitle: automation.installationInProgress
                            ? L10n.string("common.installing")
                            : L10n.string("common.install"),
                        isActionDisabled: automation.installationInProgress,
                        action: automation.installScript
                    )
                } label: {
                    Label(
                        L10n.string("setup.component_section"),
                        systemImage: "puzzlepiece.extension"
                    )
                }

                GroupBox {
                    VStack(spacing: 0) {
                        SetupRequirementRow(
                            step: 2,
                            title: L10n.string("setup.accessibility"),
                            detail: L10n.string("setup.accessibility_detail"),
                            isComplete: automation.setupStatus.accessibilityGranted,
                            actionTitle: L10n.string("setup.open_accessibility"),
                            isActionDisabled: false,
                            showsAppDragSource: true,
                            action: automation.openAccessibilitySettings
                        )

                        Divider()
                            .padding(.leading, 54)

                        SetupRequirementRow(
                            step: 3,
                            title: L10n.string("setup.automation"),
                            detail: L10n.string("setup.automation_detail"),
                            isComplete: automation.setupStatus.automationGranted,
                            actionTitle: automation.automationRequestInProgress
                                ? L10n.string("common.waiting")
                                : L10n.string("setup.allow_automation"),
                            isActionDisabled: automation.automationRequestInProgress,
                            action: automation.requestAutomationPermission
                        )
                    }
                } label: {
                    Label(
                        L10n.string("setup.permissions_section"),
                        systemImage: "hand.raised"
                    )
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)

            Divider()

            HStack {
                Menu {
                    Button(L10n.string("common.restart")) {
                        requestAppRestart()
                    }

                    Divider()

                    Button(L10n.string("common.quit")) {
                        NSApp.terminate(nil)
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help(L10n.string("setup.more_actions"))
                .accessibilityLabel(L10n.string("setup.more_actions"))

                Spacer()

                if !automation.setupStatus.isComplete {
                    Button(L10n.string("common.later")) {
                        close()
                    }
                    .keyboardShortcut(.cancelAction)

                    Button(L10n.string("common.check_again")) {
                        automation.refreshSetupStatus()
                    }
                    .keyboardShortcut(.defaultAction)
                } else {
                    Button(L10n.string("common.done")) {
                        close()
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
        }
        .frame(width: 680)
        .background(Color(nsColor: .windowBackgroundColor))
        .animation(
            .easeInOut(duration: 0.2),
            value: automation.setupStatus
        )
    }
}

@MainActor
final class SetupAssistantWindowController: NSObject, NSWindowDelegate {
    static let shared = SetupAssistantWindowController()

    private var window: NSWindow?
    private var statusMonitoringTask: Task<Void, Never>?
    private var completionHandler: (() -> Void)?

    var isPresented: Bool {
        window?.isVisible == true
    }

    private override init() {}

    func configure(completionHandler: @escaping () -> Void) {
        self.completionHandler = completionHandler
    }

    func present() {
        WindowAutomation.shared.refreshSetupStatus()

        if let window {
            startStatusMonitoring()
            NSApp.setActivationPolicy(.accessory)
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            center(window)
            return
        }

        let setupView = SetupAssistantView(
            automation: WindowAutomation.shared,
            close: { [weak self] in
                self?.window?.performClose(nil)
            }
        )
        let hostingController = NSHostingController(rootView: setupView)
        let window = NSWindow(contentViewController: hostingController)
        hostingController.view.layoutSubtreeIfNeeded()
        window.setContentSize(hostingController.view.fittingSize)
        window.title = L10n.string("setup.window_title")
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.level = .floating
        window.isReleasedWhenClosed = false
        window.delegate = self
        self.window = window
        startStatusMonitoring()

        NSApp.setActivationPolicy(.accessory)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        center(window)
    }

    private func center(_ window: NSWindow) {
        let mouseLocation = NSEvent.mouseLocation
        let targetScreen = NSScreen.screens.first {
            NSMouseInRect(mouseLocation, $0.frame, false)
        } ?? NSScreen.main ?? NSScreen.screens.first

        guard let visibleFrame = targetScreen?.visibleFrame else {
            window.center()
            return
        }

        let windowSize = window.frame.size
        let origin = NSPoint(
            x: visibleFrame.midX - windowSize.width / 2,
            y: visibleFrame.midY - windowSize.height / 2
        )
        window.setFrameOrigin(origin)
    }

    func refreshIfPresented() {
        guard isPresented else { return }
        WindowAutomation.shared.refreshSetupStatus()
    }

    func dismissIfPresented() {
        window?.performClose(nil)
    }

    func completeIfPresented() {
        guard isPresented else { return }
        completionHandler?()
    }

    private func startStatusMonitoring() {
        guard statusMonitoringTask == nil else { return }

        statusMonitoringTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 750_000_000)
                guard !Task.isCancelled,
                      let self,
                      self.isPresented
                else {
                    return
                }

                WindowAutomation.shared.refreshSetupStatus()
            }
        }
    }

    func windowWillClose(_ notification: Notification) {
        statusMonitoringTask?.cancel()
        statusMonitoringTask = nil
        window = nil

        if !AppShell.shared.isSettingsVisible,
           !ZoneEditorWindowController.shared.isPresented {
            NSApp.setActivationPolicy(.prohibited)
        }
    }
}
