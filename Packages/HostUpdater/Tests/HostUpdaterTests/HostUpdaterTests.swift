import CryptoKit
import Foundation
import Testing

@testable import HostUpdater

/// A throwaway signing key, made in memory; nothing touches the Keychain.
struct TestSigner {
    let privateKey = Curve25519.Signing.PrivateKey()
    var key: UpdateSigningKey {
        get throws { try UpdateSigningKey(base64: privateKey.publicKey.rawRepresentation.base64EncodedString()) }
    }

    func sign(_ data: Data) throws -> String {
        try privateKey.signature(for: data).base64EncodedString()
    }

    func asset(
        for data: Data, platform: HostPlatform = .macos, arch: HostArch = .universal
    ) throws -> HostUpdateFeed.Asset {
        .init(
            platform: platform, arch: arch, url: URL(string: "https://example.com/native-host")!, size: data.count,
            sha256: UpdateSigningKey.sha256(data), edSignature: try sign(data))
    }
}

@Suite struct SigningKeyTests {
    /// Captured from Sparkle 2.10.0's `sign_update --ed-key-file` with a throwaway key: CryptoKit
    /// must accept exactly what Sparkle's tools produce.
    @Test func acceptsSparkleSignatures() throws {
        let key = try UpdateSigningKey(base64: "uRiTVPHBBKd1luhRhLKVjO7aKKNz9DjXrQrqQV/qKeM=")
        let signature = "K2dfmmbNhFPBILbf86A2ITq7eh8/zfp6qGG+4fktEPUhANNEUDA6nR0NVlKeYBT0cfUWiQnLAYKMwIr+FWJEBQ=="
        #expect(key.isValidSignature(signature, for: Data("hello\n".utf8)))
        #expect(!key.isValidSignature(signature, for: Data("hello!\n".utf8)))
    }

    @Test func rejectsAMalformedKey() {
        #expect(throws: HostUpdateError.badKey) { try UpdateSigningKey(base64: "not a key") }
    }
}

@Suite struct FeedTests {
    let json = """
        {"schema": 1, "channel": "stable", "version": "1.4.0", "build": "1240", "date": "2026-10-18T07:00:00Z",
         "notes": "## New\\n- **host:** updates itself", "assets": [
          {"platform": "macos", "arch": "universal", "url": "https://example.com/native-host-macos", "size": 3, "sha256": "ab", "edSignature": "x"},
          {"platform": "linux", "arch": "x86_64", "url": "https://example.com/native-host-linux-x86_64", "size": 3, "sha256": "ab", "edSignature": "x"},
          {"platform": "freebsd", "arch": "riscv", "url": "https://example.com/other", "size": 3, "sha256": "ab", "edSignature": "x"}
        ]}
        """

    @Test func picksTheMachinesBinary() throws {
        let feed = try HostUpdateFeed.decode(Data(json.utf8))
        #expect(feed.asset(for: .macos, arch: .arm64)?.url.lastPathComponent == "native-host-macos")
        #expect(feed.asset(for: .linux, arch: .x64)?.url.lastPathComponent == "native-host-linux-x86_64")
        #expect(feed.asset(for: .linux, arch: .arm64) == nil)
        #expect(feed.assets.last?.platform == .unknown)
    }

    @Test func comparesBuildNumbers() throws {
        let feed = try HostUpdateFeed.decode(Data(json.utf8))
        #expect(feed.isNewer(than: "1239"))
        #expect(!feed.isNewer(than: "1240"))
        #expect(!feed.isNewer(than: "local"))
    }

    @Test func believesOnlySignedFeeds() throws {
        let signer = TestSigner()
        let data = Data(json.utf8)
        #expect(
            try HostUpdateFeed.verified(data, signature: try signer.sign(data), key: try signer.key).build == "1240")
        #expect(throws: HostUpdateError.badSignature("the host feed")) {
            try HostUpdateFeed.verified(data + Data(" ".utf8), signature: try signer.sign(data), key: try signer.key)
        }
    }

    @Test func refusesUnknownSchemas() {
        let future = json.replacingOccurrences(of: "\"schema\": 1", with: "\"schema\": 2")
        #expect(throws: HostUpdateError.unsupportedFeed(schema: 2)) { try HostUpdateFeed.decode(Data(future.utf8)) }
    }

    @Test func feedsLiveBesideTheAppcast() {
        #expect(
            HostUpdateSource.feedURL(repository: "binbandit/native", channel: "stable")?.absoluteString
                == "https://github.com/binbandit/native/releases/latest/download/host-feed.json")
        #expect(
            HostUpdateSource.feedURL(repository: "binbandit/native", channel: "nightly")?.absoluteString
                == "https://github.com/binbandit/native/releases/download/nightly/host-feed.json")
    }
}

@Suite struct InstallerTests {
    let root = FileManager.default.temporaryDirectory.appending(path: "host-updater-\(UUID().uuidString)")
    let signer = TestSigner()

    private func installer() throws -> HostBinaryInstaller { HostBinaryInstaller(root: root, key: try signer.key) }

    private func install(_ build: String, _ contents: String) throws {
        let data = Data(contents.utf8)
        try installer().stage(data, asset: try signer.asset(for: data), build: build)
        try installer().activate(build: build)
    }

    private func running() throws -> String {
        try String(contentsOf: try installer().executable, encoding: .utf8)
    }

    @Test func refusesTamperedDownloads() throws {
        let data = Data("good".utf8)
        let asset = try signer.asset(for: data)
        #expect(throws: HostUpdateError.checksumMismatch) {
            try installer().stage(Data("evil".utf8), asset: asset, build: "2")
        }
        var forged = asset
        forged.edSignature = try TestSigner().sign(data)
        #expect(throws: HostUpdateError.badSignature("the downloaded host")) {
            try installer().stage(data, asset: forged, build: "2")
        }
        #expect(try !installer().isStaged("2"))
    }

    @Test func switchesBuildsAndPrunesAfterConfirming() throws {
        try install("1", "one")
        #expect(try installer().startupCheck(runningBuild: "1") == .trial(attempt: 1))
        try installer().confirm(runningBuild: "1")
        try install("2", "two")
        #expect(try running() == "two")
        #expect(try installer().startupCheck(runningBuild: "2") == .trial(attempt: 1))
        try installer().confirm(runningBuild: "2")
        try install("3", "three")
        try installer().confirm(runningBuild: "3")
        #expect(try installer().ledger().current == "3")
        #expect(try installer().ledger().previous == "2")
        #expect(try !installer().isStaged("1"))
    }

    @Test func rollsBackABuildThatNeverComesUp() throws {
        try install("1", "one")
        try installer().confirm(runningBuild: "1")
        try install("2", "two")
        #expect(try installer().startupCheck(runningBuild: "2") == .trial(attempt: 1))
        #expect(try installer().startupCheck(runningBuild: "2") == .trial(attempt: 2))
        #expect(try installer().startupCheck(runningBuild: "2") == .rolledBack(from: "2", to: "1"))
        #expect(try running() == "one")
        #expect(try installer().startupCheck(runningBuild: "1") == .normal)
        #expect(try installer().ledger().lastRollback?.from == "2")
    }
}
