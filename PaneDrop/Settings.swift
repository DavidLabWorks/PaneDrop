import AppKit
import Foundation
import ServiceManagement
import SwiftUI

enum PanelPlacement: String, Codable, CaseIterable {
    case top
    case center
    case bottom
}

enum ActivationModifier: String, Codable, CaseIterable, Identifiable {
    case shift
    case command
    case option
    case function

    var id: Self { self }

    var displayName: String {
        switch self {
        case .shift: return "Shift"
        case .command: return "Command"
        case .option: return "Option"
        case .function: return "Fn"
        }
    }

    func matches(_ flags: NSEvent.ModifierFlags) -> Bool {
        let expectedFlag: NSEvent.ModifierFlags

        switch self {
        case .shift: expectedFlag = .shift
        case .command: expectedFlag = .command
        case .option: expectedFlag = .option
        case .function: expectedFlag = .function
        }

        return flags.intersection(.deviceIndependentFlagsMask)
            .contains(expectedFlag)
    }
}

struct PreferenceSnapshot: Codable, Equatable {
    var panelPlacement: PanelPlacement
    var requiresModifier: Bool
    var activationModifier: ActivationModifier
    var language: AppLanguage

    static let defaults = PreferenceSnapshot(
        panelPlacement: .center,
        requiresModifier: false,
        activationModifier: .shift,
        language: .defaultLanguage
    )
}

private struct PreferencesDocument: Codable {
    static let currentFormatVersion = 1

    let formatVersion: Int
    let values: PreferenceSnapshot
}

final class PreferencesStore: ObservableObject {
    @Published var panelPlacement = PreferenceSnapshot.defaults.panelPlacement
    @Published var requiresModifier = PreferenceSnapshot.defaults.requiresModifier
    @Published var activationModifier = PreferenceSnapshot.defaults.activationModifier
    @Published var language = PreferenceSnapshot.defaults.language

    private let disk: JSONDiskStore

    init(disk: JSONDiskStore = JSONDiskStore(fileName: "AppSettings.json")) {
        self.disk = disk
        reload()
    }

    func reload() {
        guard let data = try? disk.readData() else {
            apply(.defaults, persist: true)
            return
        }

        let decoder = JSONDecoder()
        if let document = try? decoder.decode(PreferencesDocument.self, from: data),
           document.formatVersion == PreferencesDocument.currentFormatVersion {
            apply(document.values, persist: false)
            return
        }

        AppLog.debug("Preferences file could not be decoded; defaults are being used")
        apply(.defaults, persist: false)
    }

    func save() {
        do {
            try persist()
        } catch {
            AppLog.debug("Unable to save preferences: \(error)")
        }
    }

    func persist() throws {
        try disk.write(
            PreferencesDocument(
                formatVersion: PreferencesDocument.currentFormatVersion,
                values: snapshot()
            )
        )
    }

    func snapshot() -> PreferenceSnapshot {
        PreferenceSnapshot(
            panelPlacement: panelPlacement,
            requiresModifier: requiresModifier,
            activationModifier: activationModifier,
            language: language
        )
    }

    func apply(_ snapshot: PreferenceSnapshot, persist: Bool = true) {
        panelPlacement = snapshot.panelPlacement
        requiresModifier = snapshot.requiresModifier
        activationModifier = snapshot.activationModifier
        language = snapshot.language

        if persist {
            save()
        }
    }

    func replaceAndPersist(with snapshot: PreferenceSnapshot) throws {
        let previous = self.snapshot()
        apply(snapshot, persist: false)

        do {
            try persist()
        } catch {
            apply(previous, persist: false)
            throw error
        }
    }

    func allowsPanel(for flags: NSEvent.ModifierFlags) -> Bool {
        !requiresModifier || activationModifier.matches(flags)
    }
}

struct PaneDropSettingsArchive: Codable, Equatable {
    static let currentFormatVersion = 1

    let formatVersion: Int
    let exportedAt: Date
    let preferences: PreferenceSnapshot
    let templates: TemplateLibrarySnapshot
    let startsAtLogin: Bool?

    init(
        exportedAt: Date = Date(),
        preferences: PreferenceSnapshot,
        templates: TemplateLibrarySnapshot,
        startsAtLogin: Bool? = nil
    ) {
        self.formatVersion = Self.currentFormatVersion
        self.exportedAt = exportedAt
        self.preferences = preferences
        self.templates = templates
        self.startsAtLogin = startsAtLogin
    }
}

enum SettingsArchiveError: LocalizedError {
    case unsupportedVersion(Int)

    var errorDescription: String? {
        switch self {
        case .unsupportedVersion(let version):
            return "This settings file uses unsupported format version \(version)."
        }
    }
}

final class SettingsArchiveService {
    static let shared = SettingsArchiveService(
        preferencesStore: preferences,
        templateStore: templateLibrary
    )

    private let preferencesStore: PreferencesStore
    private let templateStore: TemplateLibrary

    init(
        preferencesStore: PreferencesStore,
        templateStore: TemplateLibrary
    ) {
        self.preferencesStore = preferencesStore
        self.templateStore = templateStore
    }

    func currentArchive() -> PaneDropSettingsArchive {
        PaneDropSettingsArchive(
            preferences: preferencesStore.snapshot(),
            templates: templateStore.snapshot(),
            startsAtLogin: currentLoginItemSetting()
        )
    }

    func exportData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(currentArchive())
    }

    func restore(from data: Data) throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let archive = try decoder.decode(PaneDropSettingsArchive.self, from: data)

        guard archive.formatVersion == PaneDropSettingsArchive.currentFormatVersion else {
            throw SettingsArchiveError.unsupportedVersion(archive.formatVersion)
        }

        try templateStore.validate(archive.templates)

        let previousTemplates = templateStore.snapshot()
        let previousPreferences = preferencesStore.snapshot()
        let previousLoginItemSetting = currentLoginItemSetting()
        try templateStore.replaceAndPersist(with: archive.templates)

        do {
            try preferencesStore.replaceAndPersist(with: archive.preferences)
            if let startsAtLogin = archive.startsAtLogin {
                try setLoginItemEnabled(startsAtLogin)
            }
        } catch {
            try? templateStore.replaceAndPersist(with: previousTemplates)
            try? preferencesStore.replaceAndPersist(with: previousPreferences)
            if let previousLoginItemSetting {
                try? setLoginItemEnabled(previousLoginItemSetting)
            }
            throw error
        }
    }

    private func currentLoginItemSetting() -> Bool? {
        guard #available(macOS 13.0, *) else { return nil }
        return SMAppService.mainApp.status == .enabled
    }

    private func setLoginItemEnabled(_ enabled: Bool) throws {
        guard #available(macOS 13.0, *) else { return }
        guard currentLoginItemSetting() != enabled else { return }

        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}

let preferences = PreferencesStore()
