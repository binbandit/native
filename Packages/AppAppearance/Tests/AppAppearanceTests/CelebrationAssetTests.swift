import CryptoKit
import Foundation
import Testing

@testable import AppAppearance

/// Downloadable icon packs: the signed index, checksums, the cache, and when packs are fetched. Signed
/// with a throwaway key, never Native's.
struct CelebrationAssetTests {
    typealias F = CelebrationFixtures

    private let key = Curve25519.Signing.PrivateKey()
    private var publicKey: String { key.publicKey.rawRepresentation.base64EncodedString() }
    private static let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x01])

    private func pack(_ edition: String, dropping: String? = nil) throws -> Data {
        var images: [String: Data] = [:]
        for variant in AppIconVariant.allCases {
            for isDark in [false, true] { images[CelebrationAssets.Pack.imageName(variant, isDark: isDark)] = Self.png }
        }
        if let dropping { images[dropping] = nil }
        return try JSONEncoder().encode(CelebrationAssets.Pack(edition: edition, images: images))
    }

    private func signedIndex(_ packs: [String: Data]) throws -> (Data, String) {
        let index = CelebrationAssets.Index(
            version: "2026.10.18",
            packs: packs.mapValues {
                .init(file: "pack.json", sha256: CelebrationAssets.sha256($0), size: $0.count)
            })
        let data = try JSONEncoder().encode(index)
        return (data, try key.signature(for: data).base64EncodedString())
    }

    @Test func verifiesTheIndexAndPacks() throws {
        let valentines = try pack("valentines-day")
        let (data, signature) = try signedIndex(["valentines-day": valentines])
        let index = try CelebrationAssets.verifiedIndex(data, signature: signature, publicKey: publicKey)
        let verified = try CelebrationAssets.verifiedPack(valentines, edition: "valentines-day", index: index)
        #expect(verified.images.count == 8)

        let cache = CelebrationAssetCache(
            root: FileManager.default.temporaryDirectory.appending(path: "celebration-cache-\(UUID().uuidString)"))
        #expect(cache.icons(for: "valentines-day") == nil)
        try cache.store(verified)
        try cache.store(verified)
        let icons = try #require(cache.icons(for: "valentines-day"))
        guard case .file(let url) = icons[.nightly]?.dark else {
            Issue.record("Expected a cached file")
            return
        }
        #expect(url.lastPathComponent == "nightly-dark.png")
    }

    @Test func rejectsTamperingAndOtherKeys() throws {
        let valentines = try pack("valentines-day")
        let (data, signature) = try signedIndex(["valentines-day": valentines])
        var tampered = data
        tampered.append(0x20)
        #expect(throws: CelebrationAssets.Failure.badSignature) {
            try CelebrationAssets.verifiedIndex(tampered, signature: signature, publicKey: publicKey)
        }
        let stranger = Curve25519.Signing.PrivateKey().publicKey.rawRepresentation.base64EncodedString()
        #expect(throws: CelebrationAssets.Failure.badSignature) {
            try CelebrationAssets.verifiedIndex(data, signature: signature, publicKey: stranger)
        }
        #expect(throws: CelebrationAssets.Failure.badKey) {
            try CelebrationAssets.verifiedIndex(data, signature: signature, publicKey: "nope")
        }
        let index = try CelebrationAssets.verifiedIndex(data, signature: signature, publicKey: publicKey)
        #expect(throws: CelebrationAssets.Failure.checksumMismatch("valentines-day")) {
            try CelebrationAssets.verifiedPack(
                try pack("valentines-day", dropping: "dev-dark"), edition: "valentines-day", index: index)
        }
        #expect(throws: CelebrationAssets.Failure.notInIndex("kwanzaa")) {
            try CelebrationAssets.verifiedPack(valentines, edition: "kwanzaa", index: index)
        }
    }

    @Test func incompletePacksAreRejected() throws {
        let partial = try pack("valentines-day", dropping: "beta-light")
        let (data, signature) = try signedIndex(["valentines-day": partial])
        let index = try CelebrationAssets.verifiedIndex(data, signature: signature, publicKey: publicKey)
        #expect(throws: CelebrationAssets.Failure.incomplete("valentines-day")) {
            try CelebrationAssets.verifiedPack(partial, edition: "valentines-day", index: index)
        }
    }

    @Test func downloadedPacksApplyAndMissingOnesKeepTheBase() throws {
        let valentines = CelebrationID("native.valentines-day")
        var preferences = CelebrationPreferences()
        preferences.setEnabled(true, for: valentines)
        let waiting = F.catalog()
        let event = try #require(waiting.celebration(valentines))
        #expect(event.appIcon == .downloadable(.notDownloaded))
        #expect(event.canBeChosen(on: try F.day("2027-02-01")))
        #expect(try F.active(preferences, on: "2027-02-14", events: waiting.celebrations) == nil)

        let icons = Dictionary(
            uniqueKeysWithValues: AppIconVariant.allCases.map {
                (
                    $0,
                    AppIconImagePair(
                        light: .file(URL(filePath: "/tmp/l.png")), dark: .file(URL(filePath: "/tmp/d.png")))
                )
            })
        let downloaded = AppearanceCatalog([
            AppearanceCatalog.Plugin(
                source: ContributionSource(
                    pluginID: "celebrations", location: .builtIn, assetExists: { _ in true }, homeMarks: F.homeMarks,
                    packState: { $0 == "valentines-day" ? .ready(icons) : .notDownloaded }),
                iconSets: IconSetContributions(FirstPartyCelebrations.iconSets),
                celebrations: CelebrationContributions(FirstPartyCelebrations.celebrations))
        ])
        #expect(try F.active(preferences, on: "2027-02-14", events: downloaded.celebrations) == valentines)
        // With no Home edition of its own, Home shows its icon, exactly when the icon applies.
        let day = CelebrationPolicy.resolve(
            downloaded.celebrations, preferences: preferences, on: try F.day("2027-02-14"))
        #expect(day.active?.appliesToHome == true)
        #expect(downloaded.celebration(valentines)?.homeLook == .artwork(icons))
        #expect(event.home == .downloadable(.notDownloaded))
    }

    @Test func aChosenStyleDrivesTheIconAndItsDownload() throws {
        var preferences = F.enabled(F.muertos)
        let sugarSkull = FirstPartyCelebrations.sugarSkullIcons.id
        #expect(
            CelebrationAssets.packsDue(F.events, preferences: preferences, on: try F.day("2026-10-28")) == [
                "dia-de-muertos"
            ])
        preferences.selections[F.muertos]?.style = sugarSkull
        #expect(
            CelebrationAssets.packsDue(F.events, preferences: preferences, on: try F.day("2026-10-28")) == [
                "dia-de-muertos-sugar-skull"
            ])
        let icons = Dictionary(
            uniqueKeysWithValues: AppIconVariant.allCases.map {
                (
                    $0,
                    AppIconImagePair(
                        light: .file(URL(filePath: "/tmp/s.png")), dark: .file(URL(filePath: "/tmp/s.png")))
                )
            })
        let catalog = AppearanceCatalog([
            AppearanceCatalog.Plugin(
                source: ContributionSource(
                    pluginID: "celebrations", location: .builtIn, assetExists: { _ in true }, homeMarks: F.homeMarks,
                    packState: { $0 == "dia-de-muertos-sugar-skull" ? .ready(icons) : .notDownloaded }),
                iconSets: IconSetContributions(FirstPartyCelebrations.iconSets),
                celebrations: CelebrationContributions(FirstPartyCelebrations.celebrations))
        ])
        let day = CelebrationPolicy.resolve(catalog.celebrations, preferences: preferences, on: try F.day("2026-11-01"))
        #expect(day.active?.appliesToAppIcon == true)
        // The default style's pack isn't here, so without the choice only Home changes.
        preferences.selections[F.muertos]?.style = nil
        let plain = CelebrationPolicy.resolve(
            catalog.celebrations, preferences: preferences, on: try F.day("2026-11-01"))
        #expect(plain.active?.appliesToAppIcon == false)
        // Sets a celebration uses, alternates included, aren't offered as plain themes.
        #expect(!catalog.themes.contains { $0.id == sugarSkull })
    }

    @Test func packsAreFetchedAWeekAhead() throws {
        var preferences = CelebrationPreferences()
        preferences.setEnabled(true, for: CelebrationID("native.valentines-day"))
        preferences.setEnabled(true, for: CelebrationID("native.christmas"))
        let events = F.events
        #expect(CelebrationAssets.packsDue(events, preferences: preferences, on: try F.day("2027-01-20")) == [])
        #expect(
            CelebrationAssets.packsDue(events, preferences: preferences, on: try F.day("2027-02-08")) == [
                "valentines-day"
            ])
        #expect(
            CelebrationAssets.packsDue(events, preferences: preferences, on: try F.day("2026-12-24")) == ["christmas"])
        preferences.selections[CelebrationID("native.christmas")]?.appIcon = false
        #expect(CelebrationAssets.packsDue(events, preferences: preferences, on: try F.day("2026-12-24")) == [])
    }

    @Test func catalogueEditionsMatchTheirArtwork() {
        // Each pack's id is the artwork folder it's built from (design/app-icon/celebrations/<slug>).
        let packs = FirstPartyCelebrations.iconSets.compactMap { set -> String? in
            guard case .pack(let slug)? = set.icons else { return nil }
            return slug
        }
        #expect(Set(packs).count == packs.count)
        #expect(packs.contains("mathematics-day") && packs.contains("us-independence-day"))
        #expect(FirstPartyCelebrations.celebrations.count == Set(FirstPartyCelebrations.celebrations.map(\.id)).count)
    }
}
