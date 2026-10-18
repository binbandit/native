import Foundation
import Testing

@testable import AppAppearance

/// The `celebrations` manifest format: decoding entry by entry, validation, artwork paths and the
/// Halloween opt-in migration.
struct CelebrationContributionTests {
    typealias F = CelebrationFixtures

    private func decode<Element: AppearanceContribution>(_ json: String) throws -> ContributionList<Element> {
        try JSONDecoder().decode(ContributionList<Element>.self, from: Data(json.utf8))
    }

    private func folder() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "celebration-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url.appending(path: "icons"), withIntermediateDirectories: true)
        return url
    }

    private func icons(_ paths: (String) -> String) -> String {
        AppIconVariant.allCases.map { variant in
            "\"\(variant.rawValue)\": {\"light\": \"\(paths("\(variant.rawValue)-light"))\", \"dark\": \"\(paths("\(variant.rawValue)-dark"))\"}"
        }
        .joined(separator: ", ")
    }

    private func plugin(
        _ id: String, folder: URL, iconSets: String = "[]", celebrations: String = "[]", nativeVersion: String? = nil
    ) throws -> AppearanceCatalog.Plugin {
        AppearanceCatalog.Plugin(
            source: ContributionSource(
                pluginID: id, location: .folder(folder), homeMarks: F.homeMarks, nativeVersion: nativeVersion),
            iconSets: try decode(iconSets), celebrations: try decode(celebrations))
    }

    private var builtIn: AppearanceCatalog.Plugin {
        AppearanceCatalog.Plugin(
            source: ContributionSource(
                pluginID: "celebrations", location: .builtIn, assetExists: { _ in true }, homeMarks: F.homeMarks),
            iconSets: IconSetContributions(FirstPartyCelebrations.iconSets),
            celebrations: CelebrationContributions(FirstPartyCelebrations.celebrations))
    }

    @Test func malformedEntriesDontStopTheRest() throws {
        let contributions: CelebrationContributions = try decode(
            """
            [
              {"id": "acme.lanterns", "title": {"en": "Lanterns", "es": "Linternas"}, "aliases": ["Lantern night"],
               "calendar": {"kind": "fixed", "start": "12-30", "end": "01-02"}, "iconSet": "acme.lantern-icons"},
              {"id": "acme.broken", "title": "Broken", "calendar": {"kind": "fixed", "start": "13-40"}},
              {"title": "No id", "calendar": {"kind": "fixed", "start": "01-01"}},
              {"id": "acme.moon", "title": "Moon", "calendar": {"kind": "chinese-lunisolar", "month": 8, "day": 15}}
            ]
            """)
        #expect(contributions.valid.map(\.id.rawValue) == ["acme.lanterns", "acme.moon"])
        #expect(contributions.malformed.map(\.identifier) == ["acme.broken", "Celebration 3"])
        #expect(contributions.malformed.first?.message.contains("calendar.start") == true)
        #expect(contributions.malformed.last?.message == "Missing \"id\".")
        let lanterns = try #require(contributions.valid.first)
        #expect(lanterns.title.resolved(for: ["es-MX"]) == "Linternas")
        #expect(lanterns.title.resolved(for: ["fr"]) == "Lanterns")
        #expect(lanterns.matches("lantern NIGHT"))
        #expect(contributions.valid.last?.calendar.rule == .unsupported(kind: "chinese-lunisolar"))
    }

    @Test func notAListIsOneProblem() throws {
        let contributions: CelebrationContributions = try decode("{\"id\": \"acme.one\"}")
        #expect(contributions.valid.isEmpty)
        #expect(contributions.malformed.count == 1)
    }

    @Test func searchIgnoresAccentsAndCase() throws {
        let muertos = FirstPartyCelebrations.diaDeMuertos
        #expect(muertos.matches("dia de muertos"))
        #expect(muertos.matches("Day of the dead"))
        #expect(muertos.matches("mexico"))
        #expect(!muertos.matches("halloween"))
    }

    @Test func iconSetImagesMustStayInsideThePlugin() throws {
        let folder = try folder()
        for variant in AppIconVariant.allCases {
            for appearance in ["light", "dark"] {
                FileManager.default.createFile(
                    atPath: folder.appending(path: "icons/\(variant.rawValue)-\(appearance).png").path(
                        percentEncoded: false),
                    contents: Data())
            }
        }
        let iconSets = """
            [
              {"id": "acme.good", "name": "Good", "icons": {\(icons { "icons/\($0).png" })},
               "palette": {"light": ["#112233", "#445566"], "dark": ["#AABBCC", "#DDEEFF"]}},
              {"id": "acme.escape", "name": "Escape", "icons": {\(icons { "../\($0).png" })}},
              {"id": "acme.missing", "name": "Missing", "icons": {\(icons { "icons/\($0)-gone.png" })},
               "home": {"mark": "acme.unknown"}},
              {"id": "other.namespace", "name": "Wrong namespace"},
              {"id": "acme.good", "name": "Duplicate"},
              {"id": "acme.channel", "name": "Channel", "icons": {"canary": {"light": "a.png", "dark": "b.png"}}}
            ]
            """
        let catalog = AppearanceCatalog([try plugin("acme", folder: folder, iconSets: iconSets)])
        #expect(catalog.iconSets.map(\.id.rawValue) == ["acme.good", "acme.missing"])
        #expect(catalog.problems.map(\.identifier) == ["acme.channel", "acme.escape", "other.namespace", "acme.good"])
        #expect(catalog.problems.allSatisfy { $0.pluginID == "acme" && $0.kind == .iconSet })

        let good = try #require(catalog.iconSet(IconSetID("acme.good")))
        #expect(good.appIcon == .ready)
        #expect(good.homeStatus == .ready)
        #expect(good.home == .palette(try #require(good.contribution.palette)))
        guard case .file(let url) = good.icon(for: .nightly, isDark: true) else {
            Issue.record("Expected a file icon")
            return
        }
        #expect(url.lastPathComponent == "nightly-dark.png")
        // No celebration uses it, so it's offered as a plain app icon theme.
        #expect(catalog.themes.map(\.id) == [good.id])

        let missing = try #require(catalog.iconSet(IconSetID("acme.missing")))
        guard case .unavailable(let reason) = missing.appIcon else {
            Issue.record("Expected missing icons to be reported")
            return
        }
        #expect(reason.contains("Native Nightly dark"))
        #expect(missing.homeStatus == .unavailable("This version of Native can't draw its Home edition."))
    }

    @Test func celebrationsUseIconSetsFromAnyEnabledPlugin() throws {
        let celebrations = """
            [
              {"id": "acme.spooky", "title": "Spooky", "calendar": {"kind": "fixed", "start": "10-13"},
               "iconSet": "native.halloween"},
              {"id": "acme.orphan", "title": "Orphan", "calendar": {"kind": "fixed", "start": "10-13"},
               "iconSet": "acme.uninstalled"},
              {"id": "acme.someday", "title": "Someday", "calendar": {"kind": "fixed", "start": "10-13"}}
            ]
            """
        let catalog = AppearanceCatalog([builtIn, try plugin("acme", folder: try folder(), celebrations: celebrations)])
        let spooky = try #require(catalog.celebration(CelebrationID("acme.spooky")))
        #expect(spooky.appIcon == .ready)
        #expect(spooky.homeLook == .mark(FirstPartyCelebrations.HomeMark.halloween))
        #expect(spooky.order == FirstPartyCelebrations.celebrations.count)
        let orphan = try #require(catalog.celebration(CelebrationID("acme.orphan")))
        #expect(orphan.home == .unavailable("Its icon set \"acme.uninstalled\" isn't installed or is turned off."))
        #expect(!orphan.isApplicable)
        #expect(catalog.celebration(CelebrationID("acme.someday"))?.appIcon == .forthcoming)
        // Sets a celebration uses aren't offered all year as plain themes.
        #expect(catalog.themes.isEmpty)
    }

    @Test func containmentRejectsEscapes() throws {
        let folder = try folder()
        #expect(AppearanceCatalog.contained("icons/a.png", in: folder) != nil)
        #expect(AppearanceCatalog.contained("icons/../icons/a.png", in: folder) != nil)
        #expect(AppearanceCatalog.contained("../a.png", in: folder) == nil)
        #expect(AppearanceCatalog.contained("/etc/hosts", in: folder) == nil)
        #expect(AppearanceCatalog.contained("~/a.png", in: folder) == nil)
        try FileManager.default.createSymbolicLink(
            at: folder.appending(path: "outside"), withDestinationURL: FileManager.default.temporaryDirectory)
        #expect(AppearanceCatalog.contained("outside/a.png", in: folder) == nil)
    }

    @Test func compatibilityAndWindowsAreChecked() throws {
        let celebrations = """
            [
              {"id": "acme.future", "title": "Future", "calendar": {"kind": "fixed", "start": "05-05"},
               "compatibility": {"manifestVersion": 9}},
              {"id": "acme.newer", "title": "Newer", "calendar": {"kind": "fixed", "start": "05-05"},
               "compatibility": {"minimumNativeVersion": "2.10"}},
              {"id": "acme.long", "title": "Long", "calendar": {"kind": "fixed", "start": "05-05"},
               "display": {"windows": [{"id": "all-year", "title": "All year", "daysBefore": 180}]}},
              {"id": "acme.default", "title": "Default", "calendar": {"kind": "fixed", "start": "05-05"},
               "display": {"defaultWindow": "nope"}},
              {"id": "acme.fine", "title": "Fine", "calendar": {"kind": "fixed", "start": "05-05"},
               "compatibility": {"minimumNativeVersion": "2.9"}}
            ]
            """
        let catalog = AppearanceCatalog([
            try plugin("acme", folder: try folder(), celebrations: celebrations, nativeVersion: "2.9.1")
        ])
        #expect(catalog.celebrations.map(\.id.rawValue) == ["acme.fine"])
        #expect(catalog.problems.map(\.identifier) == ["acme.future", "acme.newer", "acme.long", "acme.default"])
    }

    @Test func builtInsUseCompiledImagesOnly() throws {
        var pathBased = FirstPartyCelebrations.halloweenIcons
        pathBased.icons = .channels(
            Dictionary(
                uniqueKeysWithValues: AppIconVariant.allCases.map {
                    ($0, IconSetImagePair(light: .path("a.png"), dark: .path("b.png")))
                }))
        let catalog = F.catalog(iconSets: [pathBased])
        #expect(catalog.iconSets.isEmpty)
        #expect(catalog.problems.first?.message.contains("compiled image") == true)
        // Its celebration stays listed, with the artwork explained.
        #expect(catalog.celebration(F.halloween)?.isApplicable == false)
    }

    @Test func firstPartyCatalogueIsValid() throws {
        let catalog = F.catalog()
        #expect(catalog.problems.isEmpty)
        #expect(catalog.celebrations.prefix(2).map(\.id) == [F.halloween, F.muertos])
        // The rest of the catalogue is listed; editions with resolvers can be chosen and download
        // their icons, the others are coming soon.
        let catalogue = catalog.celebrations.dropFirst(2)
        #expect(catalogue.allSatisfy { !$0.isApplicable })
        #expect(
            catalog.celebration(CelebrationID("native.kwanzaa"))?.nextOccurrence(
                window: nil, from: try F.day("2026-12-30"))?.core.last == (try F.day("2027-01-01")))
        #expect(
            catalog.celebration(CelebrationID("native.thanksgiving-us"))?.canBeChosen(on: try F.day("2026-10-18"))
                == true)
        #expect(catalog.celebration(CelebrationID("native.diwali"))?.canBeChosen(on: try F.day("2026-10-18")) == false)
        #expect(
            catalog.celebration(CelebrationID("native.christmas-julian"))?.iconSet?.id == IconSetID("native.christmas"))
        #expect(catalog.celebrations.contains { $0.contribution.matches("deepavali") })
        let halloween = try #require(catalog.celebration(F.halloween))
        #expect(halloween.appIcon == .ready)
        #expect(halloween.icon(for: .development, isDark: true) == .asset("AppIcon-halloween-dev-dark"))
        #expect(halloween.icon(for: .stable, isDark: false) == .asset("AppIcon-halloween-stable-light"))
        let muertos = try #require(catalog.celebration(F.muertos))
        #expect(muertos.appIcon == .downloadable(.notDownloaded))
        #expect(muertos.styles.map(\.id.rawValue) == ["native.dia-de-muertos", "native.dia-de-muertos-sugar-skull"])
        #expect(muertos.homeLook == .mark(FirstPartyCelebrations.HomeMark.diaDeMuertos))
    }

    @Test func contributionsRoundTrip() throws {
        let celebrations = try JSONEncoder().encode(CelebrationContributions(FirstPartyCelebrations.celebrations))
        #expect(
            try JSONDecoder().decode(CelebrationContributions.self, from: celebrations).valid
                == FirstPartyCelebrations.celebrations)
        let iconSets = try JSONEncoder().encode(IconSetContributions(FirstPartyCelebrations.iconSets))
        #expect(
            try JSONDecoder().decode(IconSetContributions.self, from: iconSets).valid == FirstPartyCelebrations.iconSets
        )
    }

    @Test func halloweenOptInMigrates() throws {
        let migrated = CelebrationPreferences.migrating(legacyHalloweenEnabled: true)
        #expect(migrated.selection(for: F.halloween) == .init(isEnabled: true, appIcon: true, home: true))
        #expect(migrated.selection(for: F.muertos).isEnabled == false)
        #expect(try F.active(migrated, on: "2026-10-18") == F.halloween)
        #expect(CelebrationPreferences.migrating(legacyHalloweenEnabled: false) == CelebrationPreferences())
    }

    @Test func preferencesPersist() throws {
        var preferences = F.enabled(F.halloween, F.muertos)
        preferences.selections[F.muertos]?.window = FirstPartyCelebrations.extended
        preferences.skipped = [CelebrationOccurrence.ID(eventID: F.halloween, coreStart: try F.day("2026-10-31"))]
        preferences.chosen = CelebrationOccurrence.ID(eventID: F.muertos, coreStart: try F.day("2026-11-01"))
        let data = try JSONEncoder().encode(preferences)
        #expect(try JSONDecoder().decode(CelebrationPreferences.self, from: data) == preferences)
        let json = try #require(String(data: data, encoding: .utf8))
        #expect(json.contains("native.halloween@2026-10-31"))
    }
}
