import CryptoKit
import Foundation
import Testing

@testable import AppAppearance

@MainActor
struct CelebrationDownloadTests {
    private let edition = "valentines-day"
    private let key = Curve25519.Signing.PrivateKey()
    private let png =
        Data(
            base64Encoded:
                "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=")
        ?? Data()

    private func payload() throws -> Data {
        try JSONEncoder().encode(
            CelebrationAssets.Pack(
                edition: edition,
                images: Dictionary(
                    uniqueKeysWithValues: AppIconVariant.allCases.flatMap { variant in
                        [false, true].map { (CelebrationAssets.Pack.imageName(variant, isDark: $0), png) }
                    })))
    }

    private func replies(pack: Data) throws -> [String: Data] {
        let index = try JSONEncoder().encode(
            CelebrationAssets.Index(
                version: "test",
                packs: [edition: .init(file: "pack.json", sha256: CelebrationAssets.sha256(pack), size: pack.count)]))
        return [
            "/icons/celebration-assets.json": index,
            "/icons/celebration-assets.json.sig": try key.signature(for: index).base64EncodedData(),
            "/icons/pack.json": pack,
        ]
    }

    private func model(_ fixture: CelebrationDownloadFixture) throws -> CelebrationAssetDownloads {
        let url = try #require(URL(string: "https://\(fixture.host)/icons/"))
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [CelebrationDownloadURLProtocol.self]
        let session = URLSession(configuration: configuration)
        fixture.session = session
        return CelebrationAssetDownloads(
            configuration: .download(
                .init(base: url, publicKey: key.publicKey.rawRepresentation.base64EncodedString())),
            cache: fixture.cache, session: session)
    }

    @Test func signedImagesAreDownloadedAndCachedInEveryAppearance() async throws {
        let fixture = CelebrationDownloadFixture(replies: try replies(pack: payload()))
        defer { fixture.cleanup() }
        let downloads = try model(fixture)
        #expect(downloads.state(edition) == .notDownloaded)
        let task = try #require(downloads.fetch(edition))
        #expect(downloads.fetch(edition) == nil)
        await task.value
        guard case .ready(let icons) = downloads.state(edition) else {
            Issue.record("Expected downloaded icons")
            return
        }
        #expect(icons.count == 4)
        for pair in icons.values {
            for image in [pair.light, pair.dark] {
                guard case .file(let url) = image else { Issue.record("Expected cached PNG"); continue }
                #expect(try Data(contentsOf: url) == png)
            }
        }
        downloads.configure(.unavailable(CelebrationAssetDownloads.disabled))
        #expect(downloads.state(edition) == .ready(icons))
        #expect(downloads.fetch(edition) == nil)
        #expect(fixture.requests.count == 3)
    }

    @Test func publishedLFSPointersAreRejectedAndRetryReloadsTheIndex() async throws {
        // Captured from v0.1.0 on 2026-10-24. All eight entries are LFS pointers, not PNGs.
        let url = try #require(Bundle.module.url(forResource: "celebration-valentines-day", withExtension: "json"))
        let fixture = CelebrationDownloadFixture(replies: try replies(pack: Data(contentsOf: url)))
        defer { fixture.cleanup() }
        let downloads = try model(fixture)
        await downloads.fetch(edition)?.value
        #expect(downloads.state(edition) == .failed(CelebrationAssets.Failure.incomplete(edition).localizedDescription))
        #expect(fixture.cache.icons(for: edition) == nil)
        fixture.setReplies(try replies(pack: payload()))
        await downloads.fetch(edition)?.value
        #expect(fixture.cache.icons(for: edition) != nil)
        #expect(fixture.requests.filter { $0.hasSuffix("celebration-assets.json") }.count == 2)
    }

    @Test func disabledDownloadsMakeNoRequestsAndLeaveTheBaseIcon() async throws {
        let fixture = CelebrationDownloadFixture(replies: [:])
        defer { fixture.cleanup() }
        let downloads = try model(fixture)
        downloads.configure(.unavailable(CelebrationAssetDownloads.disabled))
        #expect(downloads.fetch(edition) == nil)
        #expect(downloads.state(edition) == .unavailable(CelebrationAssetDownloads.disabled))
        #expect(fixture.requests.isEmpty)
        #expect(fixture.cache.icons(for: edition) == nil)
    }

    @Test func offlineFailureKeepsIconsUnavailableForApplication() async throws {
        let fixture = CelebrationDownloadFixture(replies: [:], failure: .notConnectedToInternet)
        defer { fixture.cleanup() }
        let downloads = try model(fixture)
        await downloads.fetch(edition)?.value
        #expect(downloads.state(edition) == .failed(CelebrationAssetDownloads.offline))
        #expect(fixture.cache.icons(for: edition) == nil)
        let requests = fixture.requests.count
        #expect(downloads.fetch(edition, retryFailed: false) == nil)
        #expect(fixture.requests.count == requests)
    }

    @Test func disablingDuringDownloadCancelsAndCannotWriteTheCache() async throws {
        let fixture = CelebrationDownloadFixture(replies: try replies(pack: payload()), heldPath: "/icons/pack.json")
        defer { fixture.cleanup() }
        let downloads = try model(fixture)
        let task = try #require(downloads.fetch(edition))
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while !fixture.requests.contains("/icons/pack.json"), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(fixture.requests.contains("/icons/pack.json"))
        downloads.configure(.unavailable(CelebrationAssetDownloads.disabled))
        await task.value
        #expect(downloads.state(edition) == .unavailable(CelebrationAssetDownloads.disabled))
        #expect(fixture.cache.icons(for: edition) == nil)
    }
}
