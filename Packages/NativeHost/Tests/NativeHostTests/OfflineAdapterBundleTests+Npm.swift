#if os(macOS)
import CryptoKit
import Exec
import Foundation
import Testing

@testable import NativeHost

/// The real npm against synthetic local tarballs, with outbound transport denied twice: by the
/// sandbox, and by a preload that records any attempt.
extension OfflineAdapterBundleTests {
    private struct NetworkDeniedRunner: CommandRunner {
        let preload: URL
        func run(_ command: Command) async throws -> CommandResult {
            var environment = command.environment
            environment["NODE_OPTIONS"] = "--require " + preload.path
            return try await LocalCommandRunner().run(
                Command(
                    "/usr/bin/sandbox-exec",
                    ["-p", "(version 1)(allow default)(deny network*)", command.executable] + command.arguments,
                    in: command.directory, environment: environment, timeout: .seconds(30)))
        }
    }

    @Test(arguments: ["complete", "missing-optional", "poisoned-cache"])
    func realNpmWithOutboundDenied(_ mode: String) async throws {
        let omitOptional = mode == "missing-optional"
        let tools = try #require(
            LocalNodeTools.installed, "BLOCKER: local Node/npm missing; never fetch a tool to run this fixture")
        let node = tools.node
        let npm = tools.npmCLI
        let scratch = temporaryRoot.appending(path: "offline-tools-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: scratch, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: scratch) }
        let preload = scratch.appending(path: "deny-network.cjs")
        let transportMarker = scratch.appending(path: "transport-attempt")
        let script = """
            const fs = require('fs');
            function deny() { fs.writeFileSync(\(String(data: try JSONEncoder().encode(transportMarker.path), encoding: .utf8) ?? "''"), 'attempt'); throw Error('network denied'); }
            for (const name of ['http', 'https']) { const m = require(name); m.request = deny; m.get = deny; }
            require('net').Socket.prototype.connect = deny;
            require('dns').lookup = deny;
            """
        try Data(script.utf8).write(to: preload)
        let runner = NetworkDeniedRunner(preload: preload)
        let environment = ["HOME": scratch.path, "PATH": node.deletingLastPathComponent().path]
        func version(_ args: [String]) async throws -> String {
            let result = try await runner.run(Command(node.path, args, in: scratch.path, environment: environment))
            try #require(result.succeeded, "Local qualification probe failed")
            return result.output.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let nodeVersion = String(try await version(["--version"]).dropFirst())
        let npmVersion = try await version([
            npm.path, "--version", "--userconfig=" + scratch.appending(path: "user.npmrc").path,
            "--globalconfig=" + scratch.appending(path: "global.npmrc").path, "--offline",
        ])
        // Each package's install script would leave `script-ran` behind if npm ran it.
        let archives = [
            "H4sIAAAAAAAC/+3TsU7DMBAG4Mw8ReTFjdSkTlsyMCNegLWLSS6VwbGDnQBVlXfHaSKQurCUCon/W846yz7L0t/K8kXuadVONXv21kQXJoJiuz3V4LyKdXH7tT7187zY5FEsoivofSddGB/9T0dmZEPsLma1+uh6R2wZszdyXlkzdvNMZGLs+dKptvOhd2TKhE/Tetw3tqI4pXjHHL32ytGC154n2btTHT0oTY8HUy74dDp10vAlf5IVT3aMDeFa23ZhktT31JKpyJSKphnzc9JWy662rvl+zDBEcClz7leNVCaE/1dm/JR/sTnPvyjWAvm/htIabzVl2u5DcufMOZLVgSc3iAcAAAAAAAAAAAAAAAAAAADAn/cJb0pP6AAoAAA=",
            "H4sIAAAAAAAC/+3UsU7DMBAG4Mw8ReTFjdS4TmiDxAPwAqxdTHKpDI4d7ASoqr47TlsxdGGBgtT/W866k3WSpd+9ql/Uhhb9sYrn4Gzyw2RULZeHGp1XWcq7r/OhXxRVuUpSmVzAGAbl4/rkOu2YVR2x+5S1+mMYPeW9UUPrfMfmKXsjH7Sz07gQUsipF2qv+yHE3o5pG1/PmGluXUNpTumaeXodtacZbwPPxLvXAz1oQ49bW8/48XbuleVz/qQanq0Z2+8T+Bun3C86pW0M/6/s+C7/8nZ1ln9ZlRL5v4Ta2eAMCeM2MbCnL8CTarY8u0E8AAAAAAAAAAAAAAAAAAAAAP69T+EmX4EAKAAA",
        ]
        var payloads: [String: Data] = [:]
        var records: [String: [String: Any]] = [:]
        for (index, name) in ["fixture", "fixture-platform"].enumerated() {
            let archive = try #require(Data(base64Encoded: archives[index]))
            let digest = SHA512.hash(data: archive)
            let hex = digest.map { String(format: "%02x", $0) }.joined()
            if !omitOptional || index == 0 {
                payloads[
                    "cache/_cacache/content-v2/sha512/\(hex.prefix(2))/\(hex.dropFirst(2).prefix(2))/\(hex.dropFirst(4))"
                ] = archive
            }
            var record: [String: Any] = [
                "version": "1.0.0", "resolved": "https://fixture.invalid/\(name).tgz",
                "integrity": "sha512-" + Data(digest).base64EncodedString(), "hasInstallScript": true,
            ]
            if index == 0 {
                record["optionalDependencies"] = ["fixture-platform": "1.0.0"]
            } else {
                record["optional"] = true
            }
            records["node_modules/" + name] = record
        }
        let f = try fixture(
            node: node, npm: npm, nodeVersion: nodeVersion, npmVersion: npmVersion, extra: payloads,
            packageRecords: records)
        defer { try? FileManager.default.removeItem(at: f.root) }
        if mode == "poisoned-cache" {
            let cachePath = try #require(payloads.keys.first)
            try Data("poison".utf8).write(to: f.source.appending(path: cachePath))
            await #expect(throws: Failure.invalidBundle) {
                try await importBundle(f, runner: Runner { _ in Issue.record("Poisoned cache must not spawn") })
            }
        } else if omitOptional {
            await #expect(throws: Failure.missingArtifact) { try await importBundle(f, runner: runner) }
            #expect(!FileManager.default.fileExists(atPath: f.destination.path))
        } else {
            let receipt = try await importBundle(f, runner: runner)
            let reused = try OfflineAdapterReceipt.reuse(
                at: f.destination, expectedSHA256: receipt.sha256, approval: f.approval, localInstallAllowed: true)
            let result = try await runner.run(
                Command(reused.command.executable, reused.command.arguments, in: scratch.path, environment: environment)
            )
            #expect(result.succeeded)
            #expect(result.output.trimmingCharacters(in: .whitespacesAndNewlines) == "fixture-ready")
            let installed = try Bundle.snapshot(f.destination)
            #expect(!installed.keys.contains { $0.hasSuffix("script-ran") })
        }
        #expect(!FileManager.default.fileExists(atPath: transportMarker.path))
        #expect(!FileManager.default.fileExists(atPath: scratch.appending(path: ".npm").path))
    }
}
#endif
