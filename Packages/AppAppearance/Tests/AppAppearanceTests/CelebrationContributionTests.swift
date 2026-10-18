import Foundation
import Testing

@testable import AppAppearance

/// The `celebrations` manifest format: decoding entry by entry, validation, artwork paths and the
/// Halloween opt-in migration.
struct CelebrationContributionTests {
    typealias F = CelebrationFixtures

    private func decode(_ json: String) throws -> CelebrationContributions {
        try JSONDecoder().decode(CelebrationContributions.self, from: Data(json.utf8))
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

    @Test func malformedEntriesDontStopTheRest() throws {
        let contributions = try decode(
            """
            [
              {"id": "acme.lanterns", "title": {"en": "Lanterns", "es": "Linternas"}, "aliases": ["Lantern night"],
               "calendar": {"kind": "fixed", "start": "12-30", "end": "01-02"},
               "artwork": {"home": {"mark": "native.halloween"}}},
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
        let contributions = try decode("{\"id\": \"acme.one\"}")
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

    @Test func folderArtworkMustStayInsideThePlugin() throws {
        let folder = try folder()
        for variant in AppIconVariant.allCases {
            for appearance in ["light", "dark"] {
                FileManager.default.createFile(
                    atPath: folder.appending(path: "icons/\(variant.rawValue)-\(appearance).png").path(percentEncoded: false),
                    contents: Data())
            }
        }
        let json = """
            [
              {"id": "acme.good", "title": "Good", "calendar": {"kind": "fixed", "start": "05-05"},
               "artwork": {"appIcon": {\(icons { "icons/\($0).png" })}}},
              {"id": "acme.escape", "title": "Escape", "calendar": {"kind": "fixed", "start": "05-05"},
               "artwork": {"appIcon": {\(icons { "../\($0).png" })}}},
              {"id": "acme.missing", "title": "Missing", "calendar": {"kind": "fixed", "start": "05-05"},
               "artwork": {"appIcon": {\(icons { "icons/\($0)-gone.png" })}, "home": {"mark": "acme.unknown"}}},
              {"id": "other.namespace", "title": "Wrong namespace", "calendar": {"kind": "fixed", "start": "05-05"}},
              {"id": "acme.good", "title": "Duplicate", "calendar": {"kind": "fixed", "start": "05-05"}}
            ]
            """
        var catalog = CelebrationCatalog()
        catalog.add(try decode(json), from: CelebrationSource(pluginID: "acme", location: .folder(folder)))
        #expect(catalog.events.map(\.id.rawValue) == ["acme.good", "acme.missing"])
        #expect(catalog.problems.map(\.identifier) == ["acme.escape", "other.namespace", "acme.good"])
        #expect(catalog.problems.allSatisfy { $0.pluginID == "acme" })

        let good = try #require(catalog.event(CelebrationID("acme.good")))
        #expect(good.appIcon == .ready)
        #expect(good.home == .notOffered)
        guard case .file(let url) = good.icon(for: .nightly, isDark: true) else {
            Issue.record("Expected a file icon")
            return
        }
        #expect(url.lastPathComponent == "nightly-dark.png")

        let missing = try #require(catalog.event(CelebrationID("acme.missing")))
        guard case .unavailable(let reason) = missing.appIcon else {
            Issue.record("Expected missing icons to be reported")
            return
        }
        #expect(reason.contains("Native Nightly dark"))
        #expect(missing.home == .unavailable("This version of Native can't draw its Home edition."))
        #expect(!missing.isApplicable)
    }

    @Test func containmentRejectsEscapes() throws {
        let folder = try folder()
        #expect(CelebrationCatalog.contained("icons/a.png", in: folder) != nil)
        #expect(CelebrationCatalog.contained("icons/../icons/a.png", in: folder) != nil)
        #expect(CelebrationCatalog.contained("../a.png", in: folder) == nil)
        #expect(CelebrationCatalog.contained("/etc/hosts", in: folder) == nil)
        #expect(CelebrationCatalog.contained("~/a.png", in: folder) == nil)
        try FileManager.default.createSymbolicLink(
            at: folder.appending(path: "outside"), withDestinationURL: FileManager.default.temporaryDirectory)
        #expect(CelebrationCatalog.contained("outside/a.png", in: folder) == nil)
    }

    @Test func compatibilityAndWindowsAreChecked() throws {
        let json = """
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
        var catalog = CelebrationCatalog()
        catalog.add(
            try decode(json),
            from: CelebrationSource(pluginID: "acme", location: .folder(try folder()), nativeVersion: "2.9.1"))
        #expect(catalog.events.map(\.id.rawValue) == ["acme.fine"])
        #expect(catalog.problems.map(\.identifier) == ["acme.future", "acme.newer", "acme.long", "acme.default"])
    }

    @Test func builtInsUseCompiledImagesOnly() throws {
        var pathBased = FirstPartyCelebrations.halloween
        pathBased.artwork.appIcon = .channels(
            Dictionary(
                uniqueKeysWithValues: AppIconVariant.allCases.map {
                    ($0, CelebrationImagePair(light: .path("a.png"), dark: .path("b.png")))
                }))
        let catalog = F.catalog([pathBased])
        #expect(catalog.events.isEmpty)
        #expect(catalog.problems.first?.message.contains("compiled image") == true)
    }

    @Test func firstPartyCatalogueIsValid() throws {
        let catalog = F.catalog()
        #expect(catalog.problems.isEmpty)
        #expect(catalog.events.map(\.id) == [F.halloween, F.muertos])
        let halloween = try #require(catalog.event(F.halloween))
        #expect(halloween.appIcon == .ready)
        #expect(halloween.icon(for: .development, isDark: true) == .asset("AppIcon-halloween-dev-dark"))
        #expect(halloween.icon(for: .stable, isDark: false) == .asset("AppIcon-halloween-stable-light"))
        let muertos = try #require(catalog.event(F.muertos))
        #expect(muertos.appIcon == .forthcoming)
        #expect(muertos.homeMark == FirstPartyCelebrations.HomeMark.diaDeMuertos)
    }

    @Test func contributionsRoundTrip() throws {
        let data = try JSONEncoder().encode(CelebrationContributions(FirstPartyCelebrations.all))
        let decoded = try JSONDecoder().decode(CelebrationContributions.self, from: data)
        #expect(decoded.valid == FirstPartyCelebrations.all)
        #expect(decoded.malformed.isEmpty)
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
