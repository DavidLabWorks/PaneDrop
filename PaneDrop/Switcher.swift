import AppKit
import SwiftUI

private enum OverlayStyle {
    static let padding: CGFloat = 14
    static let spacing: CGFloat = 10
    static let expandedCard = CGSize(width: 148, height: 168)
    static let compactCard = CGSize(width: 60, height: 60)
    static let expandedPreview: CGFloat = 124
    static let compactPreview: CGFloat = 52
    static let screenMargin: CGFloat = 36
}

private struct OverlayTemplate: Identifiable, Equatable {
    let id: UUID
    let name: String
    let zones: [ZoneDefinition]
}

struct OverlayGrid {
    let columns: Int
    let rows: Int
    let cardSize: CGSize
    let panelSize: CGSize
    let compact: Bool

    init(templateCount: Int, availableSize: CGSize) {
        let count = max(templateCount, 1)

        func arrangement(for cardSize: CGSize) -> (
            columns: Int,
            rows: Int,
            panelSize: CGSize
        ) {
            let horizontalRoom = max(
                availableSize.width - OverlayStyle.padding * 2,
                cardSize.width
            )
            let columns = max(
                1,
                min(
                    count,
                    Int(
                        (horizontalRoom + OverlayStyle.spacing)
                            / (cardSize.width + OverlayStyle.spacing)
                    )
                )
            )
            let rows = Int(ceil(Double(count) / Double(columns)))
            let width = OverlayStyle.padding * 2
                + CGFloat(columns) * cardSize.width
                + CGFloat(max(columns - 1, 0)) * OverlayStyle.spacing
            let height = OverlayStyle.padding * 2
                + CGFloat(rows) * cardSize.height
                + CGFloat(max(rows - 1, 0)) * OverlayStyle.spacing
            return (columns, rows, CGSize(width: width, height: height))
        }

        let expanded = arrangement(for: OverlayStyle.expandedCard)
        let needsCompactCards = expanded.panelSize.height > availableSize.height
        let chosen = needsCompactCards
            ? arrangement(for: OverlayStyle.compactCard)
            : expanded

        columns = chosen.columns
        rows = chosen.rows
        cardSize = needsCompactCards
            ? OverlayStyle.compactCard
            : OverlayStyle.expandedCard
        panelSize = chosen.panelSize
        compact = needsCompactCards
    }

    func cardFrame(at index: Int) -> CGRect {
        let column = index % columns
        let row = index / columns

        return CGRect(
            x: OverlayStyle.padding
                + CGFloat(column) * (cardSize.width + OverlayStyle.spacing),
            y: OverlayStyle.padding
                + CGFloat(row) * (cardSize.height + OverlayStyle.spacing),
            width: cardSize.width,
            height: cardSize.height
        )
    }

    func previewFrame(at index: Int) -> CGRect {
        let card = cardFrame(at: index)
        let side = compact
            ? OverlayStyle.compactPreview
            : OverlayStyle.expandedPreview

        return CGRect(
            x: card.midX - side / 2,
            y: card.minY + (compact ? 4 : 10),
            width: side,
            height: side
        )
    }
}

enum OverlayHitTesting {
    static func match(
        point: CGPoint,
        grid: OverlayGrid,
        templates: [(name: String, zones: [ZoneDefinition])]
    ) -> (templateName: String, zone: ZoneDefinition)? {
        for (index, template) in templates.enumerated() {
            let preview = grid.previewFrame(at: index)
            guard preview.contains(point) else { continue }

            for zone in template.zones.sorted(by: { $0.area < $1.area }) {
                if ZoneThumbnail.zoneFrame(zone, in: preview).contains(point) {
                    return (template.name, zone)
                }
            }
        }
        return nil
    }
}

private final class OverlayViewState: ObservableObject {
    @Published var templates: [OverlayTemplate] = []
    @Published var columns = 1
    @Published var compact = false
    @Published var highlightedTemplateID: UUID?
    @Published var highlightedZoneID: UUID?
}

struct ZoneThumbnail: View {
    let zones: [ZoneDefinition]
    let selected: Bool
    let highlightedZoneID: UUID?
    let side: CGFloat

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Canvas { context, canvasSize in
            let canvas = CGRect(origin: .zero, size: canvasSize)
            let background = RoundedRectangle(cornerRadius: side * 0.16)
                .path(in: canvas)
            context.fill(
                background,
                with: .color(
                    selected
                        ? Color.accentColor.opacity(0.2)
                        : Color.primary.opacity(colorScheme == .dark ? 0.08 : 0.06)
                )
            )

            for zone in zones {
                let frame = Self.zoneFrame(zone, in: canvas)
                let shape = RoundedRectangle(
                    cornerRadius: max(1, min(frame.width, frame.height) * 0.08)
                ).path(in: frame)
                let highlighted = zone.id == highlightedZoneID
                context.fill(
                    shape,
                    with: .color(
                        highlighted
                            ? Color.accentColor
                            : Color.primary.opacity(selected ? 0.55 : 0.3)
                    )
                )
                context.stroke(
                    shape,
                    with: .color(Color.white.opacity(highlighted ? 0.9 : 0.24)),
                    lineWidth: max(0.75, side * 0.012)
                )
            }
        }
        .frame(width: side, height: side)
        .overlay {
            if selected {
                RoundedRectangle(cornerRadius: side * 0.16)
                    .stroke(Color.accentColor.opacity(0.8), lineWidth: 1)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: side * 0.16))
    }

    static func zoneFrame(_ zone: ZoneDefinition, in canvas: CGRect) -> CGRect {
        let edge = canvas.width * 0.055
        let content = canvas.insetBy(dx: edge, dy: edge)
        let gap = max(1, canvas.width * 0.018)

        return CGRect(
            x: content.minX + content.width * zone.xFraction + gap,
            y: content.minY + content.height * zone.yFraction + gap,
            width: max(1, content.width * zone.widthFraction - gap * 2),
            height: max(1, content.height * zone.heightFraction - gap * 2)
        )
    }
}

private struct OverlayCard: View {
    let template: OverlayTemplate
    let compact: Bool
    let highlightedZoneID: UUID?

    var body: some View {
        VStack(spacing: compact ? 0 : 8) {
            ZoneThumbnail(
                zones: template.zones,
                selected: highlightedZoneID != nil,
                highlightedZoneID: highlightedZoneID,
                side: compact
                    ? OverlayStyle.compactPreview
                    : OverlayStyle.expandedPreview
            )

            if !compact {
                Text(template.name)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.82))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(width: OverlayStyle.expandedPreview)
            }
        }
        .padding(compact ? 4 : 10)
        .background {
            RoundedRectangle(cornerRadius: compact ? 10 : 12)
                .fill(.white.opacity(0.055))
        }
        .overlay {
            RoundedRectangle(cornerRadius: compact ? 10 : 12)
                .stroke(.white.opacity(0.1), lineWidth: 0.5)
        }
        .help(template.name)
    }
}

private struct OverlayContentView: View {
    @ObservedObject var state: OverlayViewState

    var body: some View {
        Group {
            if state.templates.isEmpty {
                Label(
                    L10n.string("template.no_templates"),
                    systemImage: "square.stack.3d.up.slash"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(24)
            } else {
                LazyVGrid(
                    columns: Array(
                        repeating: GridItem(
                            .fixed(
                                state.compact
                                    ? OverlayStyle.compactCard.width
                                    : OverlayStyle.expandedCard.width
                            ),
                            spacing: OverlayStyle.spacing
                        ),
                        count: state.columns
                    ),
                    spacing: OverlayStyle.spacing
                ) {
                    ForEach(state.templates) { template in
                        OverlayCard(
                            template: template,
                            compact: state.compact,
                            highlightedZoneID:
                                state.highlightedTemplateID == template.id
                                    ? state.highlightedZoneID
                                    : nil
                        )
                    }
                }
                .padding(OverlayStyle.padding)
            }
        }
        .background {
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
                .overlay(Color(red: 0.06, green: 0.07, blue: 0.1).opacity(0.62))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .stroke(.white.opacity(0.16), lineWidth: 0.5)
        }
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.28), radius: 20, y: 9)
        .environment(\.colorScheme, .dark)
    }
}

struct DropCandidate {
    let templateName: String
    let zone: ZoneDefinition
    let screen: NSScreen
}

final class TemplateOverlayController {
    private let window: NSPanel
    private let state = OverlayViewState()
    private var grid = OverlayGrid(templateCount: 0, availableSize: .zero)
    private var screen: NSScreen?
    private var candidate: DropCandidate?
    private var visible = false

    init() {
        let overlayStyle: NSWindow.StyleMask = [
            .borderless,
            .nonactivatingPanel
        ]
        window = NSPanel(
            contentRect: .zero,
            styleMask: overlayStyle,
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.level = .statusBar + 2
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.contentView = NSHostingView(rootView: OverlayContentView(state: state))
    }

    func present(on targetScreen: NSScreen) {
        refreshTemplates()
        position(on: targetScreen)
        updatePointer(NSEvent.mouseLocation)

        guard !visible else { return }
        visible = true
        window.alphaValue = 0
        window.orderFrontRegardless()
        window.animator().alphaValue = 1
    }

    func reposition(to targetScreen: NSScreen) {
        guard visible else { return }
        position(on: targetScreen)
        updatePointer(NSEvent.mouseLocation)
    }

    func dismiss() {
        visible = false
        candidate = nil
        state.highlightedTemplateID = nil
        state.highlightedZoneID = nil
        window.alphaValue = 0
        window.orderOut(nil)
    }

    func updatePointer(_ globalPoint: CGPoint) {
        guard visible, let screen else {
            candidate = nil
            return
        }

        let localPoint = CGPoint(
            x: globalPoint.x - window.frame.minX,
            y: window.frame.maxY - globalPoint.y
        )

        candidate = hitTest(localPoint, on: screen)
        let template = state.templates.first {
            $0.name == candidate?.templateName
        }
        state.highlightedTemplateID = template?.id
        state.highlightedZoneID = candidate?.zone.id
    }

    func currentCandidate() -> DropCandidate? {
        candidate
    }

    private func refreshTemplates() {
        state.templates = templateLibrary.orderedTemplates.map {
            OverlayTemplate(id: $0.id, name: $0.name, zones: $0.zones)
        }
    }

    private func position(on targetScreen: NSScreen) {
        screen = targetScreen
        let visibleFrame = targetScreen.visibleFrame
        let available = CGSize(
            width: max(240, visibleFrame.width - OverlayStyle.screenMargin * 2),
            height: max(100, visibleFrame.height - OverlayStyle.screenMargin * 2)
        )
        grid = OverlayGrid(
            templateCount: state.templates.count,
            availableSize: available
        )
        state.columns = grid.columns
        state.compact = grid.compact

        let originX = visibleFrame.midX - grid.panelSize.width / 2
        let originY: CGFloat

        switch preferences.panelPlacement {
        case .top:
            originY = visibleFrame.maxY
                - grid.panelSize.height
                - OverlayStyle.screenMargin
        case .center:
            originY = visibleFrame.midY - grid.panelSize.height / 2
        case .bottom:
            originY = visibleFrame.minY + OverlayStyle.screenMargin
        }

        window.setFrame(
            CGRect(origin: CGPoint(x: originX, y: originY), size: grid.panelSize),
            display: visible
        )
        if visible {
            window.orderFrontRegardless()
        }
    }

    private func hitTest(
        _ point: CGPoint,
        on screen: NSScreen
    ) -> DropCandidate? {
        let templates = state.templates.map {
            (name: $0.name, zones: $0.zones)
        }
        guard let match = OverlayHitTesting.match(
            point: point,
            grid: grid,
            templates: templates
        ) else {
            return nil
        }
        return DropCandidate(
            templateName: match.templateName,
            zone: match.zone,
            screen: screen
        )
    }
}
