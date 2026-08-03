import Foundation

#if DEBUG
enum PaneDropSelfTest {
    private struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    static func run() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("PaneDropSelfTest-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }

        let source = try makeStores(in: root.appendingPathComponent("source"))
        try verifyAppLinks()
        try verifyDefaults(source.templates)
        try verifyGeometry()
        try verifyOverlayHitTesting()
        try verifyPersistenceSchema(
            in: root.appendingPathComponent("persistence-schema")
        )
        try verifyDeferredSelectionPersistence(
            in: root.appendingPathComponent("selection")
        )

        let expectedPreferences = PreferenceSnapshot(
            panelPlacement: .bottom,
            requiresModifier: true,
            activationModifier: .option,
            language: .simplifiedChinese
        )
        source.preferences.apply(expectedPreferences)

        guard let customTemplate = source.templates.create(named: "Self Test") else {
            throw Failure(message: "Could not create a template")
        }
        customTemplate.replaceZones([
            ZoneDefinition(
                widthFraction: 0.4,
                heightFraction: 0.6,
                xFraction: 0.1,
                yFraction: 0.2
            )
        ])
        source.templates.save()

        let exportedData = try source.archiveService.exportData()
        let exported = try decodeArchive(exportedData)
        try require(
            exported.formatVersion == PaneDropSettingsArchive.currentFormatVersion,
            "Settings archive version is incorrect"
        )
        try require(
            exported.preferences == expectedPreferences,
            "Preferences were not exported"
        )
        try require(
            exported.templates.templates.contains { $0.name == "Self Test" },
            "Custom template was not exported"
        )
        try require(
            exported.startsAtLogin != nil,
            "The login-item setting was not exported"
        )

        let destination = try makeStores(
            in: root.appendingPathComponent("destination")
        )
        try destination.archiveService.restore(from: exportedData)
        try require(
            destination.preferences.snapshot() == exported.preferences,
            "Preferences did not survive export and restore"
        )
        try require(
            destination.templates.snapshot() == exported.templates,
            "Templates did not survive export and restore"
        )

        try verifyInvalidLibraryIsRejected(exported.templates, by: destination.templates)
    }

    private static func verifyAppLinks() throws {
        try require(
            AppLinks.privacyPolicy.scheme == "https",
            "Privacy policy URL must use HTTPS"
        )
        try require(
            AppLinks.support.scheme == "https",
            "Support URL must use HTTPS"
        )
        try require(
            AppLinks.privacyPolicy.host != nil && AppLinks.support.host != nil,
            "App links must have valid hosts"
        )
    }

    private static func makeStores(
        in directory: URL
    ) throws -> (
        preferences: PreferencesStore,
        templates: TemplateLibrary,
        archiveService: SettingsArchiveService
    ) {
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let preferenceStore = PreferencesStore(
            disk: JSONDiskStore(
                fileName: "AppSettings.json",
                directory: directory
            )
        )
        let templateStore = TemplateLibrary(
            disk: JSONDiskStore(
                fileName: "TemplateLibrary.json",
                directory: directory
            )
        )
        return (
            preferenceStore,
            templateStore,
            SettingsArchiveService(
                preferencesStore: preferenceStore,
                templateStore: templateStore
            )
        )
    }

    private static func decodeArchive(
        _ data: Data
    ) throws -> PaneDropSettingsArchive {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(PaneDropSettingsArchive.self, from: data)
    }

    private static func verifyDefaults(_ library: TemplateLibrary) throws {
        try require(
            library.orderedTemplateNames == [
                "Fullscreen",
                "Split Screen",
                "Focus",
                "Four Corners"
            ],
            "Built-in templates are missing or out of order"
        )
    }

    private static func verifyGeometry() throws {
        let bounds = CGRect(x: 10, y: 20, width: 300, height: 180)
        let frame = UnitZone(
            x: 0.25,
            y: 0.1,
            width: 0.5,
            height: 0.5
        ).frame(in: bounds)
        try require(
            frame == CGRect(x: 85, y: 92, width: 150, height: 90),
            "Unit-zone geometry is incorrect"
        )
        try require(
            ScreenFraction.label(for: 2.0 / 3.0) == "2/3",
            "Fraction labels are incorrect"
        )

        let normalized = ZoneDefinition(
            widthFraction: 0.01,
            heightFraction: 2,
            xFraction: 2,
            yFraction: -1
        )
        try require(
            normalized.widthFraction == 0.08
                && normalized.heightFraction == 1
                && normalized.xFraction == 0.92
                && normalized.yFraction == 0,
            "Zone normalization is incorrect"
        )
    }

    private static func verifyOverlayHitTesting() throws {
        let grid = OverlayGrid(
            templateCount: 3,
            availableSize: CGSize(width: 600, height: 400)
        )
        try require(
            grid.columns == 3 && grid.rows == 1 && !grid.compact,
            "Overlay grid arrangement is incorrect"
        )

        let leftZone = ZoneDefinition(
            widthFraction: 0.5,
            heightFraction: 1,
            xFraction: 0,
            yFraction: 0
        )
        let preview = grid.previewFrame(at: 0)
        let point = CGPoint(x: preview.minX + 20, y: preview.midY)
        let hit = OverlayHitTesting.match(
            point: point,
            grid: grid,
            templates: [(name: "Split", zones: [leftZone])]
        )
        try require(
            hit?.templateName == "Split" && hit?.zone.id == leftZone.id,
            "Overlay zone hit-testing is incorrect"
        )
        try require(
            OverlayHitTesting.match(
                point: .zero,
                grid: grid,
                templates: [(name: "Split", zones: [leftZone])]
            ) == nil,
            "Overlay hit-testing accepted a point outside the panel"
        )
    }

    private static func verifyPersistenceSchema(in directory: URL) throws {
        let stores = try makeStores(in: directory)
        stores.preferences.apply(
            PreferenceSnapshot(
                panelPlacement: .top,
                requiresModifier: true,
                activationModifier: .command,
                language: .english
            )
        )
        let persistedPreferences = try String(
            contentsOf: directory.appendingPathComponent("AppSettings.json"),
            encoding: .utf8
        )
        let persistedTemplates = try String(
            contentsOf: directory.appendingPathComponent("TemplateLibrary.json"),
            encoding: .utf8
        )
        let templateSnapshot = try JSONDecoder().decode(
            TemplateLibrarySnapshot.self,
            from: Data(persistedTemplates.utf8)
        )
        try require(
            persistedPreferences.contains("formatVersion")
                && persistedPreferences.contains("panelPlacement")
                && persistedTemplates.contains("selectedTemplateID")
                && persistedTemplates.contains("templates")
                && persistedTemplates.contains("zones")
                && persistedTemplates.contains("widthFraction")
                && templateSnapshot.formatVersion == 1,
            "PaneDrop persistence fields were not written"
        )

        let encodedZone = try JSONEncoder().encode(
            templateSnapshot.templates[0].zones[0]
        )
        let encodedZoneFields = try JSONSerialization.jsonObject(
            with: encodedZone
        ) as? [String: Any]
        try require(
            encodedZoneFields?["name"] == nil,
            "Zone name was persisted"
        )

        let incompleteZone = Data(
            """
            {
              "widthFraction": 0.5,
              "heightFraction": 1,
              "xFraction": 0,
              "yFraction": 0
            }
            """.utf8
        )
        try require(
            (try? JSONDecoder().decode(
                ZoneDefinition.self,
                from: incompleteZone
            )) == nil,
            "Incomplete zone configuration was accepted"
        )
    }

    private static func verifyDeferredSelectionPersistence(
        in directory: URL
    ) throws {
        let disk = JSONDiskStore(
            fileName: "TemplateLibrary.json",
            directory: directory
        )
        let library = TemplateLibrary(disk: disk)
        library.select(named: "Split Screen")
        try require(
            library.selectedTemplateName == "Split Screen",
            "Template selection did not update immediately"
        )

        let beforeFlush = TemplateLibrary(disk: disk)
        try require(
            beforeFlush.selectedTemplateName == "Fullscreen",
            "Template selection was written during the click handler"
        )

        library.flushPendingSelection()
        let afterFlush = TemplateLibrary(disk: disk)
        try require(
            afterFlush.selectedTemplateName == "Split Screen",
            "Deferred template selection was not persisted"
        )
    }

    private static func verifyInvalidLibraryIsRejected(
        _ snapshot: TemplateLibrarySnapshot,
        by library: TemplateLibrary
    ) throws {
        guard let first = snapshot.templates.first else {
            throw Failure(message: "Exported template library is empty")
        }
        let invalid = TemplateLibrarySnapshot(
            selectedTemplateID: first.id,
            templates: [first, first]
        )

        do {
            try library.validate(invalid)
            throw Failure(message: "Duplicate template identifiers were accepted")
        } catch is TemplateLibraryError {
        }

        let invalidName = TemplateLibrarySnapshot(
            selectedTemplateID: first.id,
            templates: [
                TemplateSnapshot(id: first.id, name: " ", zones: first.zones)
            ]
        )
        do {
            try library.validate(invalidName)
            throw Failure(message: "An invalid template name was accepted")
        } catch is TemplateLibraryError {
        }

        guard let zone = first.zones.first else {
            throw Failure(message: "The first template has no zone")
        }
        let duplicateZones = TemplateLibrarySnapshot(
            selectedTemplateID: first.id,
            templates: [
                TemplateSnapshot(
                    id: first.id,
                    name: first.name,
                    zones: [zone, zone]
                )
            ]
        )
        do {
            try library.validate(duplicateZones)
            throw Failure(message: "Duplicate zone identifiers were accepted")
        } catch is TemplateLibraryError {
        }
    }

    private static func require(
        _ condition: @autoclosure () -> Bool,
        _ message: String
    ) throws {
        guard condition() else {
            throw Failure(message: message)
        }
    }
}
#endif
