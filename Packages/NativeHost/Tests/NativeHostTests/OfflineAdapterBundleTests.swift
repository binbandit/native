import ACP
import Exec
import Foundation
import NativeHostProtocol
import Testing

@testable import NativeHost

private let offlineAdapterHashingAvailable: Bool = {
    #if canImport(CryptoKit)
    true
    #else
    false
    #endif
}()

@Suite(
    .serialized, .timeLimit(.minutes(3)),
    .enabled(
        if: offlineAdapterHashingAvailable,
        "Offline import fails closed without the existing CryptoKit hash provider"))
struct OfflineAdapterBundleTests {
    var temporaryRoot: URL {
        #if os(macOS)
        URL(filePath: "/private/tmp")
        #else
        FileManager.default.temporaryDirectory
        #endif
    }

    typealias Bundle = OfflineAdapterBundle
    typealias Failure = OfflineAdapterBundle.Failure
    let entry = "node_modules/fixture/main.js"

    struct Runner: CommandRunner {
        let body: @Sendable (Command) async throws -> Void
        func run(_ command: Command) async throws -> CommandResult {
            try await body(command)
            let version = command.arguments.first == "--version" ? "v1.0.0" : "1.0.0"
            return CommandResult(exitCode: 0, standardOutput: Data(version.utf8), standardError: Data())
        }
    }

    struct Fixture {
        let root: URL
        let source: URL
        let destination: URL
        let approval: Bundle.Approval
    }

    func fixture(
        mutate: ([String: Any]) -> [String: Any] = { $0 },
        node: URL? = nil, npm: URL? = nil, nodeVersion: String = "1.0.0", npmVersion: String = "1.0.0",
        extra: [String: Data] = [:], packageRecords: [String: [String: Any]] = [:]
    ) throws -> Fixture {
        let files = FileManager.default
        let root = temporaryRoot.appending(path: "offline-adapter-\(UUID().uuidString)")
        try files.createDirectory(at: root, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        let physical = root
        let source = physical.appending(path: "source")
        try files.createDirectory(at: source, withIntermediateDirectories: false)
        let node = node ?? physical.appending(path: "node")
        let npm = npm ?? physical.appending(path: "npm-cli.js")
        for tool in [node, npm] where !files.fileExists(atPath: tool.path) {
            try Data("// fixture tool\n".utf8).write(to: tool)
            try files.setAttributes([.posixPermissions: 0o700], ofItemAtPath: tool.path)
        }
        let package = try JSONSerialization.data(withJSONObject: ["dependencies": ["fixture": "1.0.0"]])
        var records = packageRecords
        if records.isEmpty { records = ["node_modules/fixture": ["version": "1.0.0"]] }
        records[""] = ["dependencies": ["fixture": "1.0.0"]]
        let lock = try JSONSerialization.data(withJSONObject: ["lockfileVersion": 3, "packages": records])
        var payloads = extra
        payloads["package.json"] = package
        payloads["package-lock.json"] = lock
        let identities = try payloads.keys.sorted().map { try Bundle.Payload(path: $0, bytes: payloads[$0] ?? Data()) }
        let encoded = try JSONEncoder().encode(identities)
        var manifest: [String: Any] = [
            "formatVersion": 1, "adapterID": "fixture", "adapterVersion": "1.0.0",
            "os": Bundle.platformOS, "architecture": Bundle.platformArchitecture,
            "nodeVersion": nodeVersion, "npmVersion": npmVersion, "agentVersion": "1.0.0",
            "entryPoint": entry,
            "requiredInstalledFiles": [entry] + records.keys.filter { !$0.isEmpty }.map { $0 + "/package.json" },
            "payloads": try JSONSerialization.jsonObject(with: encoded),
        ]
        manifest = mutate(manifest)
        let bytes = try JSONSerialization.data(withJSONObject: manifest, options: [.sortedKeys])
        payloads["bundle.json"] = bytes
        for (path, data) in payloads {
            let target = source.appending(path: path)
            try files.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: target)
        }
        return Fixture(
            root: physical, source: source, destination: physical.appending(path: "installed"),
            approval: Bundle.Approval(
                manifestSHA256: try ContentHash.sha256(bytes),
                lock: Bundle.ReviewedLock(
                    adapterID: "fixture", adapterVersion: "1.0.0", packageJSONSHA256: try ContentHash.sha256(package),
                    packageLockSHA256: try ContentHash.sha256(lock)),
                node: node, nodeSHA256: try ContentHash.sha256(Data(contentsOf: node)),
                npmCLI: npm, npmCLISHA256: try ContentHash.sha256(Data(contentsOf: npm)),
                nodeVersion: nodeVersion, npmVersion: npmVersion, agentVersion: "1.0.0"))
    }

    private func writeInstall(_ command: Command) throws {
        guard command.arguments.contains("ci") else { return }
        let stage = URL(filePath: try #require(command.directory))
        let target = stage.appending(path: entry)
        try FileManager.default.createDirectory(
            at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("console.log('fixture-ready')".utf8).write(to: target)
        try Data("{\"name\":\"fixture\",\"version\":\"1.0.0\"}".utf8)
            .write(to: target.deletingLastPathComponent().appending(path: "package.json"))
    }

    func importBundle(
        _ f: Fixture, runner: any CommandRunner, allowed: Bool = true
    ) async throws -> OfflineAdapterReceipt {
        try await ManagedAdapterInstaller(runner: runner).importOffline(
            from: f.source, approval: f.approval, destination: f.destination, localInstallAllowed: allowed)
    }

    @Test func deniedBeforeAnyIO() async throws {
        let f = try fixture()
        defer { try? FileManager.default.removeItem(at: f.root) }
        try FileManager.default.removeItem(at: f.source)
        let before = try FileManager.default.contentsOfDirectory(atPath: f.root.path)
        await #expect(throws: Failure.prohibitedByPolicy) {
            try await importBundle(f, runner: Runner { _ in Issue.record("No subprocess authorized") }, allowed: false)
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: f.root.path) == before)
    }

    @Test func emptyCacheLocalInstallAndReceiptReuse() async throws {
        let f = try fixture()
        defer { try? FileManager.default.removeItem(at: f.root) }
        let receipt = try await importBundle(
            f,
            runner: Runner { command in
                #expect(command.executable == f.approval.node.path)
                #expect(Set(command.environment.keys) == ["HOME", "PATH", "TMPDIR"])
                #expect(command.environment["HOME"]?.hasPrefix(try #require(command.directory)) == true)
                if command.arguments.contains("ci") {
                    for flag in [
                        "--offline", "--ignore-scripts", "--no-audit", "--no-fund", "--include=optional",
                        "--bin-links=false",
                    ] {
                        #expect(command.arguments.contains(flag))
                    }
                }
                try writeInstall(command)
            })
        #expect(receipt.command.executable == f.approval.node.path)
        #expect(receipt.command.arguments == [f.destination.appending(path: entry).path])
        let reused = try OfflineAdapterReceipt.reuse(
            at: f.destination, expectedSHA256: receipt.sha256, approval: f.approval, localInstallAllowed: true)
        #expect(reused.sha256 == receipt.sha256)
        await #expect(throws: ManagedAdapterInstaller.Failure.destinationExists) {
            try await importBundle(f, runner: Runner { _ in Issue.record("Repeated import must not spawn") })
        }
        try Data("poison".utf8).write(to: f.destination.appending(path: entry))
        #expect(throws: Failure.invalidReceipt) {
            try OfflineAdapterReceipt.reuse(
                at: f.destination, expectedSHA256: receipt.sha256, approval: f.approval, localInstallAllowed: true)
        }
    }

    /// The committed Pi pair is what `ReviewedLock.pi` names, and the importer accepts a bundle of
    /// exactly those bytes. Tarballs are left out: npm, not validation, reports them missing.
    @Test(arguments: ["reviewed", "own-lock", "unrequired-package"])
    func builtInPiLock(_ mode: String) throws {
        let pair = URL(filePath: #filePath).deletingLastPathComponent().appending(path: "../../../../adapters/pi")
        let package = try Data(contentsOf: pair.appending(path: "package.json"))
        var lock = try Data(contentsOf: pair.appending(path: "package-lock.json"))
        #expect(try ContentHash.sha256(package) == Bundle.ReviewedLock.pi.packageJSONSHA256)
        #expect(try ContentHash.sha256(lock) == Bundle.ReviewedLock.pi.packageLockSHA256)
        let records = try #require(
            (try JSONSerialization.jsonObject(with: lock) as? [String: Any])?["packages"] as? [String: Any])
        let piEntry = "node_modules/pi-acp/dist/index.js"
        var required = Set(records.keys.filter { !$0.isEmpty }.map { $0 + "/package.json" } + [piEntry])
        switch mode {
        case "own-lock": lock.append(Data("\n".utf8))
        case "unrequired-package": required.remove("node_modules/zod/package.json")
        default: break
        }
        var files = ["package.json": package, "package-lock.json": lock]
        let manifest: [String: Any] = [
            "formatVersion": 1, "adapterID": "pi-acp", "adapterVersion": "0.0.34",
            "os": Bundle.platformOS, "architecture": Bundle.platformArchitecture,
            "nodeVersion": "26.12.1", "npmVersion": "11.20.0", "agentVersion": "1.3.0", "entryPoint": piEntry,
            "requiredInstalledFiles": required.sorted(),
            "payloads": try files.keys.sorted().map {
                let payload = try Bundle.Payload(path: $0, bytes: files[$0] ?? Data())
                return ["path": payload.path, "size": payload.size, "sha256": payload.sha256] as [String: Any]
            },
        ]
        // The manifest approval is genuine in every case: only the reviewed lock may refuse it.
        files["bundle.json"] = try JSONSerialization.data(withJSONObject: manifest, options: [.sortedKeys])
        let approval = Bundle.Approval(
            manifestSHA256: try ContentHash.sha256(files["bundle.json"] ?? Data()), lock: .pi,
            node: URL(filePath: "/qualified/node"), nodeSHA256: "", npmCLI: URL(filePath: "/qualified/npm-cli.js"),
            npmCLISHA256: "", nodeVersion: "26.12.1", npmVersion: "11.20.0", agentVersion: "1.3.0")
        if mode == "reviewed" {
            #expect(try Bundle.validate(files, approval: approval).entryPoint == piEntry)
        } else {
            #expect(throws: Failure.invalidBundle) { try Bundle.validate(files, approval: approval) }
        }
    }

    @Test(arguments: [
        "formatVersion", "adapterID", "adapterVersion", "os", "architecture", "nodeVersion", "npmVersion",
        "agentVersion", "entryPoint", "requiredInstalledFiles", "duplicate", "absolute", "traversal", "empty-component",
        "cache-path", "hash", "size",
    ])
    func rejectsInvalidManifest(_ field: String) async throws {
        let f = try fixture { original in
            var manifest = original
            switch field {
            case "formatVersion": manifest[field] = 2
            case "entryPoint": manifest[field] = "../bad"
            case "requiredInstalledFiles": manifest[field] = [entry]
            case "duplicate", "absolute", "traversal", "empty-component", "cache-path", "hash", "size":
                var payloads = manifest["payloads"] as? [[String: Any]] ?? []
                switch field {
                case "duplicate": payloads.append(payloads[0])
                case "absolute": payloads[0]["path"] = "/package.json"
                case "traversal": payloads[0]["path"] = "cache/../package.json"
                case "empty-component": payloads[0]["path"] = "cache//package.json"
                case "cache-path": payloads[0]["path"] = "cache/.npmrc"
                case "hash": payloads[0]["sha256"] = String(repeating: "0", count: 64)
                default: payloads[0]["size"] = -1
                }
                manifest["payloads"] = payloads
            default: manifest[field] = "mismatch"
            }
            return manifest
        }
        defer { try? FileManager.default.removeItem(at: f.root) }
        await #expect(throws: (any Error).self) {
            try await importBundle(f, runner: Runner { _ in Issue.record("Validation must precede process") })
        }
        #expect(!FileManager.default.fileExists(atPath: f.destination.path))
        #expect(
            try FileManager.default.contentsOfDirectory(atPath: f.root.path).sorted() == [
                "node", "npm-cli.js", "source",
            ])
    }

    @Test(arguments: [
        "missing", "extra", "corrupt", "symlink", "directory-link", "root-link", "permissions", "directory-permissions",
        "empty-directory", "tool", "manifest", "hardlink",
    ])
    func rejectsUnsafeInput(_ mode: String) async throws {
        let f = try fixture()
        defer { try? FileManager.default.removeItem(at: f.root) }
        let file = f.source.appending(path: "package.json")
        let files = FileManager.default
        switch mode {
        case "missing": try files.removeItem(at: file)
        case "extra": try Data().write(to: f.source.appending(path: ".npmrc"))
        case "corrupt": try Data("corrupt".utf8).write(to: file)
        case "manifest": try Data("{}".utf8).write(to: f.source.appending(path: "bundle.json"))
        case "permissions": try files.setAttributes([.posixPermissions: 0o666], ofItemAtPath: file.path)
        case "directory-permissions": try files.setAttributes([.posixPermissions: 0o777], ofItemAtPath: f.source.path)
        case "empty-directory":
            try files.createDirectory(at: f.source.appending(path: "excess"), withIntermediateDirectories: false)
        case "tool": try Data("poison".utf8).write(to: f.approval.node)
        case "root-link":
            let other = f.root.appending(path: "moved")
            try files.moveItem(at: f.source, to: other)
            try files.createSymbolicLink(at: f.source, withDestinationURL: other)
        case "directory-link":
            try files.createSymbolicLink(at: f.source.appending(path: "cache"), withDestinationURL: f.root)
        case "hardlink": try files.linkItem(at: file, to: f.root.appending(path: "linked"))
        default:
            try files.removeItem(at: file)
            try files.createSymbolicLink(at: file, withDestinationURL: f.approval.node)
        }
        await #expect(throws: (any Error).self) {
            try await importBundle(f, runner: Runner { _ in Issue.record("Unsafe input must not spawn") })
        }
        #expect(!files.fileExists(atPath: f.destination.path))
    }

    @Test(arguments: ["cancel", "late-cancel", "failed", "missing", "changed", "race", "link", "receipt"])
    func interruptedImportsNeverPublish(_ mode: String) async throws {
        let f = try fixture()
        defer { try? FileManager.default.removeItem(at: f.root) }
        let task = Task {
            try await importBundle(
                f,
                runner: Runner { command in
                    guard command.arguments.contains("ci") else { return }
                    let stage = URL(filePath: try #require(command.directory))
                    try writeInstall(command)
                    switch mode {
                    case "cancel": throw CancellationError()
                    case "late-cancel": withUnsafeCurrentTask { $0?.cancel() }
                    case "failed": throw CommandError.timedOut("redacted", after: .seconds(300))
                    case "missing": try FileManager.default.removeItem(at: stage.appending(path: entry))
                    case "changed": try Data().write(to: stage.appending(path: "package-lock.json"))
                    case "receipt": try Data().write(to: stage.appending(path: "receipt.json"))
                    case "race":
                        try FileManager.default.createDirectory(at: f.destination, withIntermediateDirectories: false)
                    default:
                        try FileManager.default.createSymbolicLink(
                            at: stage.appending(path: "unexpected"), withDestinationURL: f.root)
                    }
                })
        }
        await #expect(throws: (any Error).self) { try await task.value }
        let remaining = try FileManager.default.contentsOfDirectory(atPath: f.root.path)
        #expect(!remaining.contains { $0.hasPrefix(".adapter-install-") })
        #expect(remaining.contains("installed") == (mode == "race"))
    }
}
