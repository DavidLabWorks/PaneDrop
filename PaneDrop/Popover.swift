import AppKit
import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers

private enum PreferencesMetrics {
    static let labelWidth: CGFloat = 156
    static let controlWidth: CGFloat = 244
    static let rowSpacing: CGFloat = 16
}

private struct PreferencesControlColumn<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        ZStack(alignment: .trailing) {
            Color.clear
                .frame(
                    width: PreferencesMetrics.controlWidth,
                    height: 28
                )
            content
        }
    }
}

private struct TooltipIcon: NSViewRepresentable {
    let systemName: String
    let tooltip: String

    func makeNSView(context: Context) -> NSImageView {
        let imageView = NSImageView()
        imageView.imageScaling = .scaleProportionallyDown
        imageView.contentTintColor = .secondaryLabelColor
        imageView.setContentHuggingPriority(.required, for: .horizontal)
        imageView.setContentHuggingPriority(.required, for: .vertical)
        update(imageView)
        return imageView
    }

    func updateNSView(_ imageView: NSImageView, context: Context) {
        update(imageView)
    }

    private func update(_ imageView: NSImageView) {
        let configuration = NSImage.SymbolConfiguration(
            pointSize: 13,
            weight: .regular
        )
        imageView.image = NSImage(
            systemSymbolName: systemName,
            accessibilityDescription: tooltip
        )?.withSymbolConfiguration(configuration)
        imageView.toolTip = tooltip
        imageView.setAccessibilityLabel(tooltip)
    }
}

private struct FooterButtonLabel: View {
    let systemName: String
    let isHovered: Bool

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 14, weight: .regular))
            .symbolRenderingMode(.monochrome)
            .frame(width: 28, height: 28)
            .contentShape(Rectangle())
            .background {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.primary.opacity(isHovered ? 0.08 : 0))
            }
    }
}

private struct FooterActionButton: View {
    let systemName: String
    let tooltip: String
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            FooterButtonLabel(
                systemName: systemName,
                isHovered: isHovered
            )
            .onHover { isHovered = $0 }
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .help(tooltip)
        .accessibilityLabel(tooltip)
    }
}

private final class FooterActionMenuController: NSObject {
    static let shared = FooterActionMenuController()

    private var importAction: (() -> Void)?
    private var exportAction: (() -> Void)?
    private var privacyAction: (() -> Void)?
    private var supportAction: (() -> Void)?

    func present(
        importTitle: String,
        exportTitle: String,
        privacyTitle: String,
        supportTitle: String,
        importAction: @escaping () -> Void,
        exportAction: @escaping () -> Void,
        privacyAction: @escaping () -> Void,
        supportAction: @escaping () -> Void
    ) {
        self.importAction = importAction
        self.exportAction = exportAction
        self.privacyAction = privacyAction
        self.supportAction = supportAction

        let menu = NSMenu()
        let importItem = NSMenuItem(
            title: importTitle,
            action: #selector(performImport),
            keyEquivalent: ""
        )
        importItem.target = self
        menu.addItem(importItem)

        let exportItem = NSMenuItem(
            title: exportTitle,
            action: #selector(performExport),
            keyEquivalent: ""
        )
        exportItem.target = self
        menu.addItem(exportItem)

        menu.addItem(.separator())
        let privacyItem = NSMenuItem(
            title: privacyTitle,
            action: #selector(openPrivacyPolicy),
            keyEquivalent: ""
        )
        privacyItem.target = self
        menu.addItem(privacyItem)

        let supportItem = NSMenuItem(
            title: supportTitle,
            action: #selector(openSupport),
            keyEquivalent: ""
        )
        supportItem.target = self
        menu.addItem(supportItem)

        menu.popUp(
            positioning: nil,
            at: NSEvent.mouseLocation,
            in: nil
        )
        self.importAction = nil
        self.exportAction = nil
        self.privacyAction = nil
        self.supportAction = nil
    }

    @objc private func performImport() {
        importAction?()
    }

    @objc private func performExport() {
        exportAction?()
    }

    @objc private func openPrivacyPolicy() {
        privacyAction?()
    }

    @objc private func openSupport() {
        supportAction?()
    }
}

private final class LoginItemPreference: ObservableObject {
    @Published var enabled = false
    @Published var errorMessage: String?

    func refresh() {
        guard #available(macOS 13.0, *) else {
            enabled = false
            return
        }
        enabled = SMAppService.mainApp.status == .enabled
    }

    func setEnabled(_ newValue: Bool) {
        guard #available(macOS 13.0, *) else { return }

        do {
            if newValue {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }

        refresh()
    }
}

private struct TemplateReorderDelegate: DropDelegate {
    let destinationName: String
    let library: TemplateLibrary
    @Binding var draggedName: String?

    func dropEntered(info: DropInfo) {
        guard let draggedName,
              draggedName != destinationName,
              let sourceIndex = library.orderedTemplateNames.firstIndex(
                of: draggedName
              ),
              let destinationIndex = library.orderedTemplateNames.firstIndex(
                of: destinationName
              ) else {
            return
        }

        let insertionIndex = destinationIndex > sourceIndex
            ? destinationIndex + 1
            : destinationIndex
        library.move(
            from: IndexSet(integer: sourceIndex),
            to: insertionIndex
        )
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        draggedName = nil
        return true
    }
}

struct SettingsView: View {
    @ObservedObject private var preferenceStore = preferences
    @ObservedObject private var library = templateLibrary
    @StateObject private var loginItem = LoginItemPreference()

    @State private var draggedTemplateName: String?
    @State private var editingTemplateName: String?
    @State private var nameDraft = ""
    @State private var feedbackMessage: String?
    @FocusState private var nameFieldFocused: Bool
    @FocusState private var templateListFocused: Bool

    private var versionText: String {
        let version = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String ?? "—"
        let build = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleVersion"
        ) as? String ?? "—"
        return L10n.string("settings.version_build", version, build)
    }

    var body: some View {
        VStack(spacing: 16) {
            titleArea

            VStack(spacing: 12) {
                templateArea
                preferenceArea
            }

            actionArea
        }
        .frame(width: 440)
        .fixedSize(horizontal: false, vertical: true)
        .alert(
            L10n.string("settings.operation_result"),
            isPresented: Binding(
                get: { feedbackMessage != nil },
                set: { if !$0 { feedbackMessage = nil } }
            )
        ) {
            Button(L10n.string("common.ok")) {
                feedbackMessage = nil
            }
        } message: {
            Text(feedbackMessage ?? "")
        }
    }

    private var titleArea: some View {
        HStack(spacing: 10) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .frame(width: 34, height: 34)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 1) {
                Text("PaneDrop")
                    .font(.system(size: 15, weight: .semibold))
                Text(L10n.string("settings.menu_subtitle"))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
    }

    private var templateArea: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(L10n.string("settings.templates"))
                    .font(.subheadline.weight(.medium))

                TooltipIcon(
                    systemName: "info.circle",
                    tooltip: L10n.string("settings.template_help")
                )
                .frame(width: 16, height: 16)

                Text("\(library.orderedTemplateNames.count)")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Spacer()

                Button(action: createTemplate) {
                    Label(L10n.string("settings.new"), systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .keyboardShortcut("n", modifiers: .command)
                .help(L10n.string("settings.new_template"))
            }

            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(library.orderedTemplateNames, id: \.self) { name in
                        templateRow(name)
                    }
                }
                .padding(5)
            }
            .focusable()
            .focused($templateListFocused)
            .onMoveCommand(perform: moveTemplateSelection)
            .paneDropFocusEffectHidden()
            .frame(height: 194)
            .background {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(
                        Color(nsColor: .controlBackgroundColor).opacity(0.6)
                    )
            }
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.secondary.opacity(0.12), lineWidth: 0.5)
            }
            .accessibilityLabel(L10n.string("settings.templates"))
            .background {
                Button(action: editSelectedTemplate) {
                    EmptyView()
                }
                .keyboardShortcut(.return, modifiers: [])
                .disabled(!templateListFocused || editingTemplateName != nil)
                .frame(width: 0, height: 0)
                .opacity(0)
            }
        }
    }

    private func templateRow(_ name: String) -> some View {
        let isSelected = library.selectedTemplateName == name
        let template = library.templatesByName[name]

        return HStack(spacing: 9) {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary.opacity(0.7))
                .frame(width: 14, height: 32)
                .contentShape(Rectangle())
                .help(L10n.string("settings.drag_to_reorder"))
                .onDrag {
                    draggedTemplateName = name
                    return NSItemProvider(object: name as NSString)
                }

            if editingTemplateName == name {
                ZoneThumbnail(
                    zones: template?.zones ?? [],
                    selected: isSelected,
                    highlightedZoneID: nil,
                    side: 34
                )
                renameControls(for: name)
            } else {
                Button {
                    templateListFocused = true
                    library.select(named: name)
                } label: {
                    HStack(spacing: 9) {
                        ZoneThumbnail(
                            zones: template?.zones ?? [],
                            selected: isSelected,
                            highlightedZoneID: nil,
                            side: 34
                        )

                        Text(name)
                            .font(.system(size: 13))
                            .lineLimit(1)
                            .truncationMode(.middle)

                        Spacer()
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Button {
                    editTemplate(name)
                } label: {
                    Image(systemName: "slider.horizontal.3")
                        .frame(width: 16, height: 16)
                }
                .buttonStyle(.plain)
                .foregroundColor(isSelected ? .accentColor : .secondary)
                .help(L10n.string("settings.edit_template"))
                .accessibilityLabel(L10n.string("settings.edit_template"))

                Menu {
                    Button(L10n.string("common.rename")) {
                        beginRename(name)
                    }
                    Button(L10n.string("settings.duplicate")) {
                        duplicateTemplate(name)
                    }
                    Divider()
                    Button(
                        L10n.string("common.delete"),
                        role: .destructive
                    ) {
                        library.remove(named: name)
                    }
                    .disabled(library.orderedTemplateNames.count == 1)
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .frame(width: 16, height: 16)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .foregroundColor(.secondary)
                .help(L10n.string("settings.template_actions"))
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background {
            RoundedRectangle(cornerRadius: 8)
                .fill(
                    isSelected
                        ? Color.accentColor.opacity(0.12)
                        : Color.clear
                )
        }
        .onDrop(
            of: [UTType.text],
            delegate: TemplateReorderDelegate(
                destinationName: name,
                library: library,
                draggedName: $draggedTemplateName
            )
        )
    }

    private func moveTemplateSelection(_ direction: MoveCommandDirection) {
        let names = library.orderedTemplateNames
        guard !names.isEmpty else { return }

        let currentIndex = names.firstIndex(of: library.selectedTemplateName) ?? 0
        let nextIndex: Int

        switch direction {
        case .up:
            nextIndex = max(currentIndex - 1, 0)
        case .down:
            nextIndex = min(currentIndex + 1, names.count - 1)
        default:
            return
        }

        library.select(named: names[nextIndex])
    }

    private func editSelectedTemplate() {
        guard templateListFocused else { return }
        editTemplate(library.selectedTemplateName)
    }

    private func renameControls(for originalName: String) -> some View {
        HStack(spacing: 6) {
            TextField(
                L10n.string("settings.template_name"),
                text: Binding(
                    get: { nameDraft },
                    set: { nameDraft = TemplateNaming.limited($0) }
                )
            )
            .textFieldStyle(.roundedBorder)
            .focused($nameFieldFocused)
            .onSubmit {
                finishRename(originalName)
            }

            Button {
                finishRename(originalName)
            } label: {
                Image(systemName: "checkmark")
            }
            .buttonStyle(.plain)
            .disabled(renameError(for: originalName) != nil)

            Button {
                cancelRename()
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.plain)
        }
    }

    private var preferenceArea: some View {
        VStack(spacing: 12) {
            preferenceRow(L10n.string("settings.template_panel_position")) {
                Picker("", selection: $preferenceStore.panelPlacement) {
                    Text(L10n.string("position.top")).tag(PanelPlacement.top)
                    Text(L10n.string("position.center")).tag(PanelPlacement.center)
                    Text(L10n.string("position.bottom")).tag(PanelPlacement.bottom)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .onChange(of: preferenceStore.panelPlacement) { _ in
                    preferenceStore.save()
                }
            }

            preferenceRow(L10n.string("settings.require_modifier")) {
                Toggle("", isOn: $preferenceStore.requiresModifier)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .onChange(of: preferenceStore.requiresModifier) { _ in
                        preferenceStore.save()
                    }
            }

            preferenceRow(L10n.string("settings.modifier_key")) {
                Picker("", selection: $preferenceStore.activationModifier) {
                    ForEach(ActivationModifier.allCases) { modifier in
                        Text(modifier.displayName).tag(modifier)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .disabled(!preferenceStore.requiresModifier)
                .onChange(of: preferenceStore.activationModifier) { _ in
                    preferenceStore.save()
                }
            }

            preferenceRow(L10n.string("language.title")) {
                Picker("", selection: $preferenceStore.language) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(language.displayName).tag(language)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .onChange(of: preferenceStore.language) { _ in
                    preferenceStore.save()
                    NotificationCenter.default.post(
                        name: .paneDropLanguageDidChange,
                        object: nil
                    )
                }
            }

            if #available(macOS 13.0, *) {
                preferenceRow(L10n.string("settings.start_at_login")) {
                    Toggle(
                        "",
                        isOn: Binding(
                            get: { loginItem.enabled },
                            set: {
                                loginItem.setEnabled($0)
                                if let message = loginItem.errorMessage {
                                    feedbackMessage = message
                                }
                            }
                        )
                    )
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .onAppear { loginItem.refresh() }
                    .onReceive(
                        NotificationCenter.default.publisher(
                            for: NSApplication.didBecomeActiveNotification
                        )
                    ) { _ in
                        loginItem.refresh()
                    }
                }
            }
        }
        .padding(12)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.6))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.secondary.opacity(0.12), lineWidth: 0.5)
        }
    }

    private func preferenceRow<Control: View>(
        _ title: String,
        @ViewBuilder control: () -> Control
    ) -> some View {
        HStack(spacing: PreferencesMetrics.rowSpacing) {
            Text(title)
                .font(.subheadline)
                .frame(
                    width: PreferencesMetrics.labelWidth,
                    alignment: .leading
                )

            PreferencesControlColumn {
                control()
            }
        }
    }

    private var actionArea: some View {
        HStack(spacing: 0) {
            Text(versionText)
                .font(.caption2)
                .foregroundStyle(.secondary)

            Spacer()

            FooterActionButton(
                systemName: "ellipsis.circle",
                tooltip: L10n.string("settings.more_actions"),
                action: {
                    FooterActionMenuController.shared.present(
                        importTitle: L10n.string("settings.import"),
                        exportTitle: L10n.string("settings.export"),
                        privacyTitle: L10n.string(
                            "settings.privacy_policy"
                        ),
                        supportTitle: L10n.string("settings.support"),
                        importAction: importSettings,
                        exportAction: exportSettings,
                        privacyAction: {
                            NSWorkspace.shared.open(AppLinks.privacyPolicy)
                        },
                        supportAction: {
                            NSWorkspace.shared.open(AppLinks.support)
                        }
                    )
                }
            )

            Divider()
                .frame(height: 16)
                .padding(.horizontal, 6)

            FooterActionButton(
                systemName: "power.circle",
                tooltip: L10n.string("settings.quit_panedrop"),
                action: { NSApp.terminate(nil) }
            )
        }
        .frame(height: 28)
    }

    private func createTemplate() {
        let baseName = L10n.string("settings.new_template")
        let name = library.templatesByName[baseName] == nil
            ? baseName
            : TemplateNaming.availableCopyName(
                basedOn: baseName,
                isAlreadyUsed: { library.templatesByName[$0] != nil }
            )

        guard library.create(named: name) != nil else { return }
        let opened = ZoneEditorWindowController.shared.show(
            templateName: name,
            startsRenaming: true,
            isNewTemplate: true
        )
        if !opened {
            library.remove(named: name)
        }
    }

    private func editTemplate(_ name: String) {
        cancelRename()
        library.select(named: name)
        ZoneEditorWindowController.shared.show(templateName: name)
    }

    private func beginRename(_ name: String) {
        library.select(named: name)
        editingTemplateName = name
        nameDraft = name
        DispatchQueue.main.async {
            nameFieldFocused = true
        }
    }

    private func cancelRename() {
        editingTemplateName = nil
        nameDraft = ""
        nameFieldFocused = false
    }

    private func renameError(for originalName: String) -> String? {
        TemplateNaming.error(
            for: nameDraft,
            excluding: originalName,
            isAlreadyUsed: { library.templatesByName[$0] != nil }
        )
    }

    private func finishRename(_ originalName: String) {
        guard renameError(for: originalName) == nil else { return }
        _ = library.rename(originalName, to: nameDraft)
        cancelRename()
    }

    private func duplicateTemplate(_ name: String) {
        let copyName = TemplateNaming.availableCopyName(
            basedOn: name,
            isAlreadyUsed: { library.templatesByName[$0] != nil }
        )
        guard library.duplicate(name, as: copyName) != nil else { return }
        ZoneEditorWindowController.shared.show(templateName: copyName)
    }

    private func exportSettings() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = "PaneDrop Settings.json"

        AppShell.shared.performModalInteraction {
            guard panel.runModal() == .OK, let destination = panel.url else {
                return
            }

            do {
                let data = try SettingsArchiveService.shared.exportData()
                try data.write(to: destination, options: [.atomic])
                feedbackMessage = L10n.string("settings.export_success")
            } catch {
                feedbackMessage = error.localizedDescription
            }
        }
    }

    private func importSettings() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false

        AppShell.shared.performModalInteraction {
            guard panel.runModal() == .OK, let source = panel.url else {
                return
            }

            let confirmation = NSAlert()
            confirmation.alertStyle = .warning
            confirmation.messageText = L10n.string(
                "settings.import_confirm_title"
            )
            confirmation.informativeText = L10n.string(
                "settings.import_confirm_detail"
            )
            confirmation.addButton(withTitle: L10n.string("settings.import"))
            confirmation.addButton(withTitle: L10n.string("common.cancel"))
            guard confirmation.runModal() == .alertFirstButtonReturn else {
                return
            }

            do {
                let data = try Data(contentsOf: source)
                try SettingsArchiveService.shared.restore(from: data)
                NotificationCenter.default.post(
                    name: .paneDropLanguageDidChange,
                    object: nil
                )
                feedbackMessage = L10n.string("settings.import_success")
            } catch {
                feedbackMessage = error.localizedDescription
            }
        }
    }
}

private extension View {
    @ViewBuilder
    func paneDropFocusEffectHidden() -> some View {
        if #available(macOS 14.0, *) {
            focusEffectDisabled()
        } else {
            self
        }
    }
}

struct MenuBarSettingsRoot: View {
    @ObservedObject private var state = appState

    var body: some View {
        if state.isReady {
            SettingsView()
                .padding()
        } else {
            VStack(spacing: 12) {
                Text(L10n.string("settings.loading"))
                ProgressView()
            }
            .frame(width: 240, height: 110)
        }
    }
}

#Preview {
    SettingsView()
        .padding()
}
