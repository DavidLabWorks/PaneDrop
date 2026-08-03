//
// PaneDrop, macOS system utility for managing windows on your Mac.
//

import AppKit
import SwiftUI

private struct ZoneDraft: Identifiable, Equatable {
    let id: Int
    var x: CGFloat
    var y: CGFloat
    var width: CGFloat
    var height: CGFloat

    init(id: Int, config: ZoneDefinition) {
        self.id = id
        self.x = config.xFraction
        self.y = config.yFraction
        self.width = config.widthFraction
        self.height = config.heightFraction
        normalize()
    }

    init(
        id: Int,
        x: CGFloat,
        y: CGFloat,
        width: CGFloat,
        height: CGFloat
    ) {
        self.id = id
        self.x = x
        self.y = y
        self.width = width
        self.height = height
        normalize()
    }

    mutating func normalize() {
        width = min(max(width, 0.08), 1)
        height = min(max(height, 0.08), 1)
        x = min(max(x, 0), 1 - width)
        y = min(max(y, 0), 1 - height)
    }

    func zoneDefinition(number: Int) -> ZoneDefinition {
        ZoneDefinition(
            number: number,
            widthFraction: width,
            heightFraction: height,
            xFraction: x,
            yFraction: y
        )
    }
}

private final class ZoneEditorModel: ObservableObject {
    @Published var templateName: String
    @Published var zones: [ZoneDraft]
    @Published var selectedZoneID: Int?

    private let template: WindowTemplate
    fileprivate let originalTemplateName: String
    private let originalZones: [ZoneDraft]
    private(set) var isNewTemplate: Bool

    init(
        templateName: String,
        template: WindowTemplate,
        configs: [ZoneDefinition],
        isNewTemplate: Bool
    ) {
        self.templateName = templateName
        self.originalTemplateName = templateName
        self.template = template
        self.isNewTemplate = isNewTemplate

        let sortedConfigs = configs.sorted {
            $0.number < $1.number
        }
        let drafts = sortedConfigs.enumerated().map { index, config in
            ZoneDraft(id: index + 1, config: config)
        }

        self.zones = drafts
        self.originalZones = drafts
        self.selectedZoneID = drafts.first?.id
    }

    var hasChanges: Bool {
        isNewTemplate
            || zones != originalZones
            || normalizedTemplateName != originalTemplateName
    }

    var templateNameError: String? {
        TemplateNaming.error(
            for: templateName,
            excluding: originalTemplateName,
            isAlreadyUsed: { templateLibrary.templatesByName[$0] != nil }
        )
    }

    var canSave: Bool {
        hasChanges && templateNameError == nil
    }

    var canDeleteSelectedZone: Bool {
        selectedZoneID != nil && zones.count > 1
    }

    func select(_ id: Int) {
        selectedZoneID = id
    }

    func addZone() {
        let id = (zones.map(\.id).max() ?? 0) + 1
        let stagger = CGFloat(zones.count % 5) * 0.04
        let zone = ZoneDraft(
            id: id,
            x: 0.2 + stagger,
            y: 0.2 + stagger,
            width: 0.42,
            height: 0.42
        )

        zones.append(zone)
        selectedZoneID = id
    }

    func deleteSelectedZone() {
        guard canDeleteSelectedZone, let selectedZoneID else { return }

        let deletedIndex = zones.firstIndex { $0.id == selectedZoneID } ?? 0
        zones.removeAll { $0.id == selectedZoneID }
        let nextIndex = min(deletedIndex, zones.count - 1)
        self.selectedZoneID = zones[nextIndex].id
    }

    func updateZone(_ id: Int, transform: (inout ZoneDraft) -> Void) {
        guard let index = zones.firstIndex(where: { $0.id == id }) else { return }

        transform(&zones[index])
        zones[index].normalize()
    }

    func updateSelectedZone(
        _ keyPath: WritableKeyPath<ZoneDraft, CGFloat>,
        value: CGFloat
    ) {
        guard let selectedZoneID else { return }
        updateZone(selectedZoneID) { zone in
            if keyPath == \ZoneDraft.x {
                zone.x = min(max(value, 0), 1 - zone.width)
            } else if keyPath == \ZoneDraft.y {
                zone.y = min(max(value, 0), 1 - zone.height)
            } else if keyPath == \ZoneDraft.width {
                zone.width = min(max(value, 0.08), 1 - zone.x)
            } else if keyPath == \ZoneDraft.height {
                zone.height = min(max(value, 0.08), 1 - zone.y)
            }
        }
    }

    func applyPreset(_ preset: ZonePreset) {
        guard let selectedZoneID else { return }

        let unitZone = preset.unitZone
        updateZone(selectedZoneID) { zone in
            zone.x = unitZone.x
            zone.y = unitZone.y
            zone.width = unitZone.width
            zone.height = unitZone.height
        }
    }

    @discardableResult
    func save() -> Bool {
        guard templateLibrary.templatesByName[originalTemplateName] === template,
              templateNameError == nil else {
            return false
        }

        let configs = zones.enumerated().map { index, zone in
            zone.zoneDefinition(number: index + 1)
        }
        if zones != originalZones {
            template.replaceZones(configs)
        }

        if normalizedTemplateName == originalTemplateName {
            templateLibrary.save()
        } else if !templateLibrary.rename(
            originalTemplateName,
            to: normalizedTemplateName
        ) {
            return false
        }

        isNewTemplate = false
        return true
    }

    private var normalizedTemplateName: String {
        TemplateNaming.sanitized(templateName)
    }
}

final class ZoneEditorWindowController: NSObject, NSWindowDelegate {
    static let shared = ZoneEditorWindowController()

    private var window: NSWindow?
    private var model: ZoneEditorModel?
    private var closesWithoutConfirmation = false
    private var keyMonitor: Any?

    var isPresented: Bool {
        window != nil
    }

    @discardableResult
    func show(
        templateName: String,
        startsRenaming: Bool = false,
        isNewTemplate: Bool = false
    ) -> Bool {
        guard let template = templateLibrary.templatesByName[templateName] else {
            return false
        }

        if let window, window.isVisible,
           model?.templateName == templateName {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return true
        }

        if window?.isVisible == true {
            guard requestClose() else { return false }
        }

        let configs = template.zones
        let model = ZoneEditorModel(
            templateName: templateName,
            template: template,
            configs: configs,
            isNewTemplate: isNewTemplate
        )
        let rootView = ZoneEditorView(
            model: model,
            startsRenaming: startsRenaming,
            onSave: { [weak self] in
                self?.saveAndClose()
            },
            onCancel: { [weak self] in
                self?.discardAndClose()
            }
        )

        let editorWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 980, height: 650),
            styleMask: [
                .titled,
                .closable,
                .miniaturizable,
                .resizable
            ],
            backing: .buffered,
            defer: false
        )
        editorWindow.title = L10n.string(
            "editor.edit_template_title",
            templateName
        )
        editorWindow.isReleasedWhenClosed = false
        editorWindow.minSize = NSSize(width: 860, height: 580)
        editorWindow.level = .normal
        editorWindow.tabbingMode = .disallowed
        let didRestoreFrame = editorWindow.setFrameUsingName(
            "PaneDrop.TemplateEditor"
        )
        editorWindow.setFrameAutosaveName("PaneDrop.TemplateEditor")
        editorWindow.contentView = NSHostingView(rootView: rootView)
        editorWindow.delegate = self
        if !didRestoreFrame {
            editorWindow.center()
        }

        self.model = model
        self.window = editorWindow
        startKeyMonitor()

        AppShell.shared.dismissSettings()

        DispatchQueue.main.async {
            if ProcessInfo.processInfo.environment["PANEDROP_UI_REVIEW"] != "1" {
                NSApp.setActivationPolicy(.accessory)
            }
            editorWindow.makeKeyAndOrderFront(nil)
            editorWindow.makeFirstResponder(nil)
            NSApp.activate(ignoringOtherApps: true)
        }

        return true
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard !closesWithoutConfirmation else {
            return true
        }

        return resolveUnsavedChanges()
    }

    func confirmApplicationTermination() -> Bool {
        guard window?.isVisible == true else { return true }
        return resolveUnsavedChanges()
    }

    private func resolveUnsavedChanges() -> Bool {
        guard model?.hasChanges == true else { return true }

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = L10n.string("editor.unsaved_title")
        alert.informativeText = L10n.string("editor.unsaved_detail")
        alert.addButton(withTitle: L10n.string("common.save"))
        alert.addButton(withTitle: L10n.string("common.discard"))
        alert.addButton(withTitle: L10n.string("common.cancel"))

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            return saveDraft()
        case .alertSecondButtonReturn:
            return true
        default:
            return false
        }
    }

    func windowWillClose(_ notification: Notification) {
        stopKeyMonitor()
        discardNewTemplateIfNeeded()
        window = nil
        model = nil
        if !AppShell.shared.isSettingsVisible {
            NSApp.setActivationPolicy(.prohibited)
        }
    }

    private func closeWithoutConfirmation() {
        guard let window else { return }

        closesWithoutConfirmation = true
        window.close()
        closesWithoutConfirmation = false
    }

    private func discardAndClose() {
        closeWithoutConfirmation()
    }

    private func discardNewTemplateIfNeeded() {
        guard let model, model.isNewTemplate else { return }
        templateLibrary.remove(named: model.originalTemplateName)
    }

    private func requestClose() -> Bool {
        guard resolveUnsavedChanges() else { return false }
        closeWithoutConfirmation()
        return true
    }

    private func startKeyMonitor() {
        stopKeyMonitor()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) {
            [weak self] event in
            guard let self, self.window?.isKeyWindow == true else {
                return event
            }

            if event.keyCode == 53 {
                _ = self.requestClose()
                return nil
            }

            if event.keyCode == 1,
               event.modifierFlags.intersection(.deviceIndependentFlagsMask)
                .contains(.command) {
                self.saveAndClose()
                return nil
            }

            return event
        }
    }

    private func stopKeyMonitor() {
        guard let keyMonitor else { return }
        NSEvent.removeMonitor(keyMonitor)
        self.keyMonitor = nil
    }

    private func saveAndClose() {
        guard saveDraft() else { return }
        closeWithoutConfirmation()
    }

    private func saveDraft() -> Bool {
        guard let model, model.canSave else {
            return false
        }

        guard model.save() else {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = L10n.string("editor.could_not_save")
            alert.informativeText = L10n.string("editor.template_missing")
            alert.addButton(withTitle: L10n.string("common.ok"))
            alert.runModal()
            return false
        }

        return true
    }
}

private struct ZoneEditorView: View {
    @ObservedObject var model: ZoneEditorModel

    let startsRenaming: Bool
    let onSave: () -> Void
    let onCancel: () -> Void

    @State private var templateNameDraft: String
    @FocusState private var isTemplateNameFieldFocused: Bool

    init(
        model: ZoneEditorModel,
        startsRenaming: Bool,
        onSave: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.model = model
        self.startsRenaming = startsRenaming
        self.onSave = onSave
        self.onCancel = onCancel
        self._templateNameDraft = State(
            initialValue: model.templateName
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            HSplitView {
                canvasWorkspace
                    .frame(
                        minWidth: 540,
                        maxWidth: .infinity,
                        maxHeight: .infinity
                    )

                inspector
                    .frame(
                        minWidth: 300,
                        idealWidth: 320,
                        maxWidth: 360,
                        maxHeight: .infinity
                    )
            }

            Divider()

            footer
        }
        .frame(minWidth: 860, minHeight: 580)
        .background(Color(NSColor.windowBackgroundColor))
        .onAppear {
            DispatchQueue.main.async {
                isTemplateNameFieldFocused = startsRenaming
            }
        }
    }

    private var canvasWorkspace: some View {
        VStack(spacing: 0) {
            HStack {
                Text(L10n.string("editor.screen_preview"))
                    .font(.subheadline.weight(.semibold))

                Spacer()

                Text(L10n.string("editor.drag_resize_hint"))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 20)
            .frame(height: 44)

            Divider()

            GeometryReader { geometry in
                let canvasSize = fittedCanvasSize(in: geometry.size)

                ZoneEditorCanvas(
                    model: model,
                    size: canvasSize
                )
                .frame(width: canvasSize.width, height: canvasSize.height)
                .position(
                    x: geometry.size.width / 2,
                    y: geometry.size.height / 2
                )
            }
            .padding(24)
            .background(Color(NSColor.windowBackgroundColor))
        }
    }

    private var inspector: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                templateSection

                Divider()

                zoneSection

                if selectedZone != nil {
                    Divider()

                    metricSection

                    Divider()

                    presetSection
                } else {
                    Label(
                        L10n.string("editor.select_zone"),
                        systemImage: "rectangle.dashed"
                    )
                    .font(.callout)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color(NSColor.controlBackgroundColor))
    }

    private var templateSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(
                L10n.string("settings.template_name"),
                systemImage: "square.grid.2x2"
            )
            .font(.subheadline.weight(.semibold))

            TextField(
                L10n.string("settings.template_name"),
                text: $templateNameDraft
            )
            .textFieldStyle(.roundedBorder)
            .focused($isTemplateNameFieldFocused)
            .onChange(of: templateNameDraft) { newName in
                let limitedName = TemplateNaming.limited(newName)
                if limitedName != newName {
                    templateNameDraft = limitedName
                    return
                }
                model.templateName = limitedName
            }

            if let templateNameError = model.templateNameError {
                Text(templateNameError)
                    .font(.caption)
                    .foregroundColor(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var zoneSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(L10n.string("editor.zones"))
                    .font(.subheadline.weight(.semibold))

                Text("\(model.zones.count)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .monospacedDigit()

                Spacer()

                Button(action: model.addZone) {
                    Image(systemName: "plus")
                        .frame(width: 14, height: 14)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help(L10n.string("editor.add_zone"))
                .accessibilityLabel(L10n.string("editor.add_zone"))

                Button(action: model.deleteSelectedZone) {
                    Image(systemName: "trash")
                        .frame(width: 14, height: 14)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .foregroundColor(.red)
                .disabled(!model.canDeleteSelectedZone)
                .help(L10n.string("editor.delete_zone"))
                .accessibilityLabel(L10n.string("editor.delete_zone"))
            }

            ScrollView(.horizontal, showsIndicators: false) {
                Picker(
                    L10n.string("editor.zones"),
                    selection: selectedZoneBinding
                ) {
                    ForEach(Array(model.zones.enumerated()), id: \.element.id) {
                        index,
                        zone in
                        Text("\(index + 1)")
                            .tag(zone.id)
                            .accessibilityLabel(
                                L10n.string("editor.zone_number", index + 1)
                            )
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .fixedSize()
            }
        }
    }

    private var metricSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L10n.string("editor.position_size"))
                .font(.subheadline.weight(.semibold))

            ZoneMetricRow(
                title: "X",
                value: metricBinding(\.x)
            )
            ZoneMetricRow(
                title: "Y",
                value: metricBinding(\.y)
            )
            ZoneMetricRow(
                title: L10n.string("editor.width"),
                value: metricBinding(\.width)
            )
            ZoneMetricRow(
                title: L10n.string("editor.height"),
                value: metricBinding(\.height)
            )
        }
    }

    private var presetSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L10n.string("editor.quick_position"))
                .font(.subheadline.weight(.semibold))

            presetGrid
        }
    }

    private var presetGrid: some View {
        let presets: [ZonePreset] = [
            .fullScreen,
            .centered,
            .leftHalf,
            .rightHalf,
            .topLeft,
            .topRight,
            .bottomLeft,
            .bottomRight
        ]
        let columns = [
            GridItem(.flexible(), spacing: 6),
            GridItem(.flexible(), spacing: 6),
            GridItem(.flexible(), spacing: 6),
            GridItem(.flexible(), spacing: 6)
        ]

        return LazyVGrid(columns: columns, spacing: 6) {
            ForEach(presets, id: \.self) { preset in
                Button(action: {
                    model.applyPreset(preset)
                }) {
                    Image(preset.assetName)
                        .resizable()
                        .renderingMode(.template)
                        .scaledToFit()
                        .frame(width: 20, height: 20)
                        .frame(maxWidth: .infinity, minHeight: 30)
                }
                .buttonStyle(.bordered)
                .help(preset.localizedName)
                .accessibilityLabel(preset.localizedName)
            }
        }
    }

    private var footer: some View {
        HStack {
            Label(
                L10n.string("editor.changes_apply_after_save"),
                systemImage: "info.circle"
            )
            .font(.caption)
            .foregroundColor(.secondary)

            Spacer()

            Button(L10n.string("common.cancel"), action: onCancel)
                .keyboardShortcut(.cancelAction)
                .accessibilityLabel(L10n.string("common.cancel"))

            Button(L10n.string("common.save"), action: onSave)
                .buttonStyle(.borderedProminent)
                .keyboardShortcut("s", modifiers: .command)
                .disabled(!model.canSave)
                .accessibilityLabel(L10n.string("common.save"))
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(Color(NSColor.windowBackgroundColor))
    }

    private var selectedZone: ZoneDraft? {
        guard let selectedZoneID = model.selectedZoneID else { return nil }
        return model.zones.first { $0.id == selectedZoneID }
    }

    private var selectedZoneBinding: Binding<Int> {
        Binding(
            get: {
                model.selectedZoneID ?? model.zones.first?.id ?? 0
            },
            set: model.select
        )
    }

    private func metricBinding(
        _ keyPath: WritableKeyPath<ZoneDraft, CGFloat>
    ) -> Binding<CGFloat> {
        Binding(
            get: {
                selectedZone?[keyPath: keyPath] ?? 0
            },
            set: {
                model.updateSelectedZone(keyPath, value: $0)
            }
        )
    }

    private func fittedCanvasSize(in availableSize: CGSize) -> CGSize {
        let aspectRatio: CGFloat = 16 / 10
        let width = min(
            availableSize.width,
            availableSize.height * aspectRatio
        )
        return CGSize(
            width: max(width, 1),
            height: max(width / aspectRatio, 1)
        )
    }
}

private struct ZoneMetricRow: View {
    let title: String
    @Binding var value: CGFloat

    init(title: String, value: Binding<CGFloat>) {
        self.title = title
        self._value = value
    }

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 42, alignment: .leading)

            Slider(value: $value, in: 0...1)

            Text("\(Int((value * 100).rounded()))%")
                .font(.system(.caption, design: .monospaced))
                .frame(width: 38, alignment: .trailing)
        }
    }
}

private struct ZoneEditorCanvas: View {
    @ObservedObject var model: ZoneEditorModel
    let size: CGSize

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.black.opacity(0.035))

            grid

            ForEach(Array(model.zones.enumerated()), id: \.element.id) {
                index,
                zone in
                ZoneCanvasItem(
                    zone: zone,
                    number: index + 1,
                    isSelected: model.selectedZoneID == zone.id,
                    canvasSize: size,
                    onSelect: {
                        model.select(zone.id)
                    },
                    onMove: { x, y in
                        model.updateZone(zone.id) {
                            $0.x = x
                            $0.y = y
                        }
                    },
                    onResize: { x, y, width, height in
                        model.updateZone(zone.id) {
                            $0.x = x
                            $0.y = y
                            $0.width = width
                            $0.height = height
                        }
                    }
                )
            }
        }
        .coordinateSpace(name: "zoneEditorCanvas")
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
        )
    }

    private var grid: some View {
        Path { path in
            for index in 1..<10 {
                let x = size.width * CGFloat(index) / 10
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
            }
            for index in 1..<10 {
                let y = size.height * CGFloat(index) / 10
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
            }
        }
        .stroke(Color.secondary.opacity(0.08), lineWidth: 1)
    }
}

private struct ZoneCanvasItem: View {
    private enum DragOperation {
        case move(ZoneDraft)
        case resize(ZoneDraft)
    }

    let zone: ZoneDraft
    let number: Int
    let isSelected: Bool
    let canvasSize: CGSize
    let onSelect: () -> Void
    let onMove: (_ x: CGFloat, _ y: CGFloat) -> Void
    let onResize: (
        _ x: CGFloat,
        _ y: CGFloat,
        _ width: CGFloat,
        _ height: CGFloat
    ) -> Void

    @State private var dragOperation: DragOperation?

    var body: some View {
        let width = max(zone.width * canvasSize.width, 1)
        let height = max(zone.height * canvasSize.height, 1)

        ZStack(alignment: .bottomTrailing) {
            RoundedRectangle(cornerRadius: 8)
                .fill(
                    Color.accentColor.opacity(isSelected ? 0.28 : 0.14)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(
                            isSelected
                                ? Color.accentColor
                                : Color.accentColor.opacity(0.42),
                            lineWidth: isSelected ? 2 : 1
                        )
                )

            Text("\(number)")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.accentColor)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .allowsHitTesting(false)

            if isSelected {
                Circle()
                    .fill(Color.accentColor)
                    .overlay(
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(.white)
                    )
                    .frame(width: 18, height: 18)
                    .padding(4)
            }
        }
        .frame(width: width, height: height)
        .contentShape(Rectangle())
        .gesture(interactionGesture)
        .accessibilityLabel(L10n.string("editor.zone_number", number))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction {
            onSelect()
        }
        .shadow(
            color: isSelected ? Color.accentColor.opacity(0.16) : .clear,
            radius: 8
        )
        .padding(.leading, zone.x * canvasSize.width)
        .padding(.top, zone.y * canvasSize.height)
        .zIndex(isSelected ? 2 : 1)
    }

    private var interactionGesture: some Gesture {
        DragGesture(
            minimumDistance: 0,
            coordinateSpace: .named("zoneEditorCanvas")
        )
            .onChanged { value in
                if dragOperation == nil {
                    let handleHitSize: CGFloat = 32
                    let zoneRightEdge = (zone.x + zone.width)
                        * canvasSize.width
                    let zoneBottomEdge = (zone.y + zone.height)
                        * canvasSize.height
                    let startsOnResizeHandle = isSelected
                        && value.startLocation.x
                            >= zoneRightEdge - handleHitSize
                        && value.startLocation.x <= zoneRightEdge
                        && value.startLocation.y
                            >= zoneBottomEdge - handleHitSize
                        && value.startLocation.y <= zoneBottomEdge

                    if startsOnResizeHandle {
                        dragOperation = .resize(zone)
                    } else {
                        dragOperation = .move(zone)
                        onSelect()
                    }
                }

                switch dragOperation {
                case .move(let start):
                    let x = start.x
                        + value.translation.width / canvasSize.width
                    let y = start.y
                        + value.translation.height / canvasSize.height
                    onMove(
                        min(max(x, 0), 1 - start.width),
                        min(max(y, 0), 1 - start.height)
                    )
                case .resize(let start):
                    let resizedWidth = min(
                        max(
                            0.08,
                            start.width
                                + value.translation.width / canvasSize.width
                        ),
                        1 - start.x
                    )
                    let resizedHeight = min(
                        max(
                            0.08,
                            start.height
                                + value.translation.height / canvasSize.height
                        ),
                        1 - start.y
                    )
                    onResize(
                        start.x,
                        start.y,
                        resizedWidth,
                        resizedHeight
                    )
                case nil:
                    break
                }
            }
            .onEnded { _ in
                dragOperation = nil
            }
    }
}
