import AppKit
import Foundation
import SwiftUI

struct JSONDiskStore {
    let fileURL: URL

    init(fileName: String, directory: URL? = nil) {
        let fileManager = FileManager.default
        let bundleDirectory = directory ?? {
            let supportDirectory = fileManager.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first ?? fileManager.temporaryDirectory
            return supportDirectory.appendingPathComponent(
                Bundle.main.bundleIdentifier ?? "com.ruobin521.panedrop",
                isDirectory: true
            )
        }()

        fileURL = bundleDirectory.appendingPathComponent(fileName)
    }

    func readData() throws -> Data {
        try Data(contentsOf: fileURL)
    }

    func write<Value: Encodable>(_ value: Value) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let encoded = try encoder.encode(value)
        try encoded.write(to: fileURL, options: [.atomic])
    }
}

enum TemplateNaming {
    static let maximumLength = 32

    static func limited(_ candidate: String) -> String {
        String(candidate.prefix(maximumLength))
    }

    static func sanitized(_ candidate: String) -> String {
        String(
            candidate
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .prefix(maximumLength)
        )
    }

    static func error(
        for candidate: String,
        excluding existingName: String? = nil,
        isAlreadyUsed: (String) -> Bool
    ) -> String? {
        let cleanName = sanitized(candidate)

        guard !cleanName.isEmpty else {
            return L10n.string("template.name_empty")
        }
        guard candidate.count <= maximumLength else {
            return L10n.string("template.name_too_long", maximumLength)
        }
        guard cleanName == existingName || !isAlreadyUsed(cleanName) else {
            return L10n.string("template.name_exists")
        }

        return nil
    }

    static func availableCopyName(
        basedOn sourceName: String,
        isAlreadyUsed: (String) -> Bool
    ) -> String {
        let root = copyRoot(from: sanitized(sourceName))
        var ordinal = 1

        while true {
            let suffix = L10n.duplicateSuffix(number: ordinal)
            let allowedRootLength = max(1, maximumLength - suffix.count)
            let candidate = String(root.prefix(allowedRootLength))
                .trimmingCharacters(in: .whitespaces) + suffix

            if !isAlreadyUsed(candidate) {
                return candidate
            }
            ordinal += 1
        }
    }

    private static func copyRoot(from name: String) -> String {
        let markers = [" Copy", " 副本"]

        for marker in markers where name.hasSuffix(marker) {
            return String(name.dropLast(marker.count))
        }

        for marker in [" Copy ", " 副本 "] {
            guard let range = name.range(of: marker, options: .backwards),
                  Int(name[range.upperBound...]) != nil else {
                continue
            }
            return String(name[..<range.lowerBound])
        }

        return name
    }
}

struct ZoneDefinition: Codable, Equatable, Identifiable {
    let id: UUID
    var number: Int
    var widthFraction: CGFloat
    var heightFraction: CGFloat
    var xFraction: CGFloat
    var yFraction: CGFloat

    init(
        id: UUID = UUID(),
        number: Int = 1,
        widthFraction: CGFloat,
        heightFraction: CGFloat,
        xFraction: CGFloat,
        yFraction: CGFloat
    ) {
        self.id = id
        self.number = number
        self.widthFraction = widthFraction
        self.heightFraction = heightFraction
        self.xFraction = xFraction
        self.yFraction = yFraction
        normalize()
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)

        id = try values.decode(UUID.self, forKey: .id)
        number = try values.decode(Int.self, forKey: .number)
        widthFraction = try values.decode(CGFloat.self, forKey: .widthFraction)
        heightFraction = try values.decode(CGFloat.self, forKey: .heightFraction)
        xFraction = try values.decode(CGFloat.self, forKey: .xFraction)
        yFraction = try values.decode(CGFloat.self, forKey: .yFraction)
        normalize()
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(id, forKey: .id)
        try values.encode(number, forKey: .number)
        try values.encode(widthFraction, forKey: .widthFraction)
        try values.encode(heightFraction, forKey: .heightFraction)
        try values.encode(xFraction, forKey: .xFraction)
        try values.encode(yFraction, forKey: .yFraction)
    }

    static var starterZone: ZoneDefinition {
        ZoneDefinition(
            widthFraction: 0.5,
            heightFraction: 0.5,
            xFraction: 0.25,
            yFraction: 0.25
        )
    }

    var area: CGFloat {
        widthFraction * heightFraction
    }

    func appKitFrame(on screen: NSScreen) -> CGRect {
        UnitZone(
            x: xFraction,
            y: yFraction,
            width: widthFraction,
            height: heightFraction
        ).frame(in: screen.visibleFrame)
    }

    func accessibilityFrame(on screen: NSScreen) -> CGRect {
        let visibleFrame = screen.visibleFrame
        let width = visibleFrame.width * widthFraction
        let height = visibleFrame.height * heightFraction
        let topInset = screen.frame.maxY - visibleFrame.maxY

        return CGRect(
            x: visibleFrame.minX + visibleFrame.width * xFraction,
            y: DisplayLocator.shared.accessibilityTop(for: screen)
                + topInset
                + visibleFrame.height * yFraction,
            width: width,
            height: height
        )
    }

    private mutating func normalize() {
        widthFraction = widthFraction.limited(to: 0.08...1)
        heightFraction = heightFraction.limited(to: 0.08...1)
        xFraction = xFraction.limited(to: 0...(1 - widthFraction))
        yFraction = yFraction.limited(to: 0...(1 - heightFraction))
        number = max(number, 1)
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case number
        case widthFraction
        case heightFraction
        case xFraction
        case yFraction
    }
}

final class WindowTemplate: Identifiable {
    let id: UUID
    var name: String
    private(set) var zones: [ZoneDefinition]

    init(id: UUID = UUID(), name: String, zones: [ZoneDefinition]) {
        self.id = id
        self.name = name
        self.zones = Self.numbered(zones)
    }

    func replaceZones(_ newZones: [ZoneDefinition]) {
        zones = Self.numbered(newZones)
    }

    private static func numbered(_ zones: [ZoneDefinition]) -> [ZoneDefinition] {
        zones.enumerated().map { index, original in
            var zone = original
            zone.number = index + 1
            return zone
        }
    }
}

struct TemplateSnapshot: Codable, Equatable, Identifiable {
    let id: UUID
    var name: String
    var zones: [ZoneDefinition]
}

struct TemplateLibrarySnapshot: Codable, Equatable {
    static let currentFormatVersion = 1

    let formatVersion: Int
    var selectedTemplateID: UUID?
    var templates: [TemplateSnapshot]

    init(selectedTemplateID: UUID?, templates: [TemplateSnapshot]) {
        formatVersion = Self.currentFormatVersion
        self.selectedTemplateID = selectedTemplateID
        self.templates = templates
    }
}

enum TemplateLibraryError: LocalizedError {
    case unsupportedVersion(Int)
    case emptyLibrary
    case duplicateIdentifier
    case duplicateZoneIdentifier
    case duplicateName(String)
    case invalidName(String)
    case emptyTemplate(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedVersion(let version):
            return "Unsupported template format version \(version)."
        case .emptyLibrary:
            return "A template library must contain at least one template."
        case .duplicateIdentifier:
            return "The settings file contains duplicate template identifiers."
        case .duplicateZoneIdentifier:
            return "The settings file contains duplicate zone identifiers."
        case .duplicateName(let name):
            return "The settings file contains the duplicate template name “\(name)”."
        case .invalidName(let name):
            return "The settings file contains the invalid template name “\(name)”."
        case .emptyTemplate(let name):
            return "The template “\(name)” does not contain any zones."
        }
    }
}

final class TemplateLibrary: ObservableObject {
    @Published private(set) var templatesByName: [String: WindowTemplate] = [:]
    @Published private(set) var orderedTemplateNames: [String] = []
    @Published private(set) var selectedTemplateName = ""

    private let disk: JSONDiskStore
    private var selectionNeedsPersistence = false

    var selectedTemplate: WindowTemplate {
        templatesByName[selectedTemplateName]
            ?? orderedTemplates.first
            ?? Self.builtInTemplates()[0]
    }

    var orderedTemplates: [WindowTemplate] {
        orderedTemplateNames.compactMap { templatesByName[$0] }
    }

    init(disk: JSONDiskStore = JSONDiskStore(fileName: "TemplateLibrary.json")) {
        self.disk = disk
        reload()
    }

    func reload() {
        guard let data = try? disk.readData() else {
            installBuiltIns()
            save()
            return
        }

        let decoder = JSONDecoder()

        if let document = try? decoder.decode(TemplateLibrarySnapshot.self, from: data) {
            do {
                try validate(document)
                install(document)
            } catch {
                AppLog.debug("Template library was rejected: \(error)")
                installBuiltIns()
            }
            return
        }

        AppLog.debug("Template file could not be decoded; built-in templates were restored")
        installBuiltIns()
    }

    func save() {
        objectWillChange.send()
        do {
            try persist()
            selectionNeedsPersistence = false
        } catch {
            AppLog.debug("Unable to save templates: \(error)")
        }
    }

    func persist() throws {
        try disk.write(snapshot())
    }

    func snapshot() -> TemplateLibrarySnapshot {
        TemplateLibrarySnapshot(
            selectedTemplateID: templatesByName[selectedTemplateName]?.id,
            templates: orderedTemplates.map {
                TemplateSnapshot(id: $0.id, name: $0.name, zones: $0.zones)
            }
        )
    }

    func validate(_ snapshot: TemplateLibrarySnapshot) throws {
        guard snapshot.formatVersion == TemplateLibrarySnapshot.currentFormatVersion else {
            throw TemplateLibraryError.unsupportedVersion(snapshot.formatVersion)
        }
        guard !snapshot.templates.isEmpty else {
            throw TemplateLibraryError.emptyLibrary
        }

        var identifiers = Set<UUID>()
        var zoneIdentifiers = Set<UUID>()
        var names = Set<String>()

        for template in snapshot.templates {
            guard identifiers.insert(template.id).inserted else {
                throw TemplateLibraryError.duplicateIdentifier
            }
            guard names.insert(template.name).inserted else {
                throw TemplateLibraryError.duplicateName(template.name)
            }
            guard TemplateNaming.sanitized(template.name) == template.name,
                  !template.name.isEmpty else {
                throw TemplateLibraryError.invalidName(template.name)
            }
            guard !template.zones.isEmpty else {
                throw TemplateLibraryError.emptyTemplate(template.name)
            }
            for zone in template.zones {
                guard zoneIdentifiers.insert(zone.id).inserted else {
                    throw TemplateLibraryError.duplicateZoneIdentifier
                }
            }
        }
    }

    func replaceAndPersist(with snapshot: TemplateLibrarySnapshot) throws {
        try validate(snapshot)
        let previous = self.snapshot()
        install(snapshot)

        do {
            try persist()
            selectionNeedsPersistence = false
        } catch {
            install(previous)
            throw error
        }
    }

    func select(named name: String) {
        guard templatesByName[name] != nil,
              selectedTemplateName != name else {
            return
        }
        selectedTemplateName = name
        selectionNeedsPersistence = true
    }

    func flushPendingSelection() {
        guard selectionNeedsPersistence else { return }
        save()
    }

    func move(from source: IndexSet, to destination: Int) {
        orderedTemplateNames.move(fromOffsets: source, toOffset: destination)
        save()
    }

    @discardableResult
    func create(named proposedName: String) -> WindowTemplate? {
        guard TemplateNaming.error(
            for: proposedName,
            isAlreadyUsed: { templatesByName[$0] != nil }
        ) == nil else {
            return nil
        }

        let name = TemplateNaming.sanitized(proposedName)
        let template = WindowTemplate(name: name, zones: [.starterZone])
        templatesByName[name] = template
        orderedTemplateNames.append(name)
        selectedTemplateName = name
        save()
        return template
    }

    @discardableResult
    func rename(_ oldName: String, to proposedName: String) -> Bool {
        guard let template = templatesByName[oldName],
              TemplateNaming.error(
                for: proposedName,
                excluding: oldName,
                isAlreadyUsed: { templatesByName[$0] != nil }
              ) == nil else {
            return false
        }

        let newName = TemplateNaming.sanitized(proposedName)
        guard newName != oldName else { return true }

        templatesByName.removeValue(forKey: oldName)
        template.name = newName
        templatesByName[newName] = template

        if let index = orderedTemplateNames.firstIndex(of: oldName) {
            orderedTemplateNames[index] = newName
        }
        if selectedTemplateName == oldName {
            selectedTemplateName = newName
        }

        save()
        return true
    }

    func remove(named name: String) {
        guard templatesByName.count > 1,
              templatesByName.removeValue(forKey: name) != nil else {
            return
        }

        orderedTemplateNames.removeAll { $0 == name }
        if selectedTemplateName == name {
            selectedTemplateName = orderedTemplateNames[0]
        }
        save()
    }

    @discardableResult
    func duplicate(_ sourceName: String, as proposedName: String) -> WindowTemplate? {
        guard let source = templatesByName[sourceName],
              TemplateNaming.error(
                for: proposedName,
                isAlreadyUsed: { templatesByName[$0] != nil }
              ) == nil else {
            return nil
        }

        let name = TemplateNaming.sanitized(proposedName)
        let zones = source.zones.map {
            ZoneDefinition(
                number: $0.number,
                widthFraction: $0.widthFraction,
                heightFraction: $0.heightFraction,
                xFraction: $0.xFraction,
                yFraction: $0.yFraction
            )
        }
        let copy = WindowTemplate(name: name, zones: zones)
        templatesByName[name] = copy

        let insertionIndex = (orderedTemplateNames.firstIndex(of: sourceName) ?? -1) + 1
        orderedTemplateNames.insert(name, at: insertionIndex)
        selectedTemplateName = name
        save()
        return copy
    }

    private func install(_ snapshot: TemplateLibrarySnapshot) {
        let templates = snapshot.templates.map {
            WindowTemplate(id: $0.id, name: $0.name, zones: $0.zones)
        }

        templatesByName = Dictionary(
            uniqueKeysWithValues: templates.map { ($0.name, $0) }
        )
        orderedTemplateNames = templates.map(\.name)

        let selectedName = templates.first {
            $0.id == snapshot.selectedTemplateID
        }?.name
        selectedTemplateName = selectedName ?? orderedTemplateNames[0]
    }

    private func installBuiltIns() {
        let templates = Self.builtInTemplates()
        templatesByName = Dictionary(
            uniqueKeysWithValues: templates.map { ($0.name, $0) }
        )
        orderedTemplateNames = templates.map(\.name)
        selectedTemplateName = templates[0].name
    }

    private static func builtInTemplates() -> [WindowTemplate] {
        [
            WindowTemplate(
                id: UUID(uuidString: "6944D221-41F0-4F10-81EC-000000000001")!,
                name: "Fullscreen",
                zones: [
                    ZoneDefinition(
                        widthFraction: 1,
                        heightFraction: 1,
                        xFraction: 0,
                        yFraction: 0
                    )
                ]
            ),
            WindowTemplate(
                id: UUID(uuidString: "6944D221-41F0-4F10-81EC-000000000002")!,
                name: "Split Screen",
                zones: [
                    ZoneDefinition(
                        number: 1,
                        widthFraction: 0.5,
                        heightFraction: 1,
                        xFraction: 0,
                        yFraction: 0
                    ),
                    ZoneDefinition(
                        number: 2,
                        widthFraction: 0.5,
                        heightFraction: 1,
                        xFraction: 0.5,
                        yFraction: 0
                    )
                ]
            ),
            WindowTemplate(
                id: UUID(uuidString: "6944D221-41F0-4F10-81EC-000000000003")!,
                name: "Focus",
                zones: [
                    ZoneDefinition(
                        widthFraction: 0.6,
                        heightFraction: 0.6,
                        xFraction: 0.2,
                        yFraction: 0.2
                    )
                ]
            ),
            WindowTemplate(
                id: UUID(uuidString: "6944D221-41F0-4F10-81EC-000000000004")!,
                name: "Four Corners",
                zones: [
                    ZoneDefinition(
                        number: 1,
                        widthFraction: 0.5,
                        heightFraction: 0.5,
                        xFraction: 0,
                        yFraction: 0
                    ),
                    ZoneDefinition(
                        number: 2,
                        widthFraction: 0.5,
                        heightFraction: 0.5,
                        xFraction: 0.5,
                        yFraction: 0
                    ),
                    ZoneDefinition(
                        number: 3,
                        widthFraction: 0.5,
                        heightFraction: 0.5,
                        xFraction: 0,
                        yFraction: 0.5
                    ),
                    ZoneDefinition(
                        number: 4,
                        widthFraction: 0.5,
                        heightFraction: 0.5,
                        xFraction: 0.5,
                        yFraction: 0.5
                    )
                ]
            )
        ]
    }
}

let templateLibrary = TemplateLibrary()
