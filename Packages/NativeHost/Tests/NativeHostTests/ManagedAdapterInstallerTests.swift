import ACP
import Exec
import Foundation
import NativeHost
import Testing

@Suite(.timeLimit(.minutes(1)))
struct ManagedAdapterInstallerTests {
    private typealias Failure = ManagedAdapterInstaller.Failure
    private let manifest = Data("{\"name\":\"fixture\",\"version\":\"1.0.0\",\"private\":true}\n".utf8)
    private let lock = Data(
        "{\"name\":\"fixture\",\"version\":\"1.0.0\",\"lockfileVersion\":3,\"packages\":{\"\":{\"name\":\"fixture\",\"version\":\"1.0.0\"}}}\n"
            .utf8)
    private let entry = "node_modules/fixture/main.js"
    private let environment = [
        "PATH": "/usr/bin:/bin", "FIXTURE_SECRET": "never-log-this", "npm_config_ignore_scripts": "false",
        "NPM_CONFIG_IGNORE_SCRIPTS": "false", "npm_config_global": "true", "npm_config_audit": "true",
        "npm_config_fund": "true", "npm_config_cache": "/must-not-use", "NPM_CONFIG_CACHE": "/also-not-used",
    ]

    private struct Runner: CommandRunner {
        let body: @Sendable (Command) async throws -> Void
        func run(_ command: Command) async throws -> CommandResult {
            try await body(command)
            return CommandResult(exitCode: 0, standardOutput: Data(), standardError: Data())
        }
    }

    private func scratch() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appending(path: "managed-adapter-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        return root.resolvingSymlinksInPath()
    }

    private func writeEntry(_ stage: URL) throws {
        let file = stage.appending(path: entry)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("throw new Error('must never launch');\n".utf8).write(to: file)
    }

    private func install(
        _ runner: any CommandRunner, at destination: URL, entryPoint: String? = nil
    ) async throws
        -> AgentCommand
    {
        try await ManagedAdapterInstaller(runner: runner).install(
            auditedPackageJSON: manifest, auditedPackageLock: lock, destination: destination,
            entryPoint: entryPoint ?? entry, arguments: ["--stdio", "literal space"], environment: environment,
            workingDirectory: destination.deletingLastPathComponent(), allowedByPolicy: true)
    }

    @Test(arguments: [false, true])
    func publishesAndReturnsNodeCommand(_ linked: Bool) async throws {
        let root = try scratch()
        defer { try? FileManager.default.removeItem(at: root) }
        let destination = root.appending(path: "install with spaces")
        let command = try await install(
            Runner { command in
                let stage = URL(filePath: try #require(command.directory))
                #expect(command.executable == "npm")
                #expect(
                    command.arguments == [
                        "ci", "--ignore-scripts", "--no-audit", "--no-fund", "--global=false", "--prefix", stage.path,
                        "--cache", stage.appending(path: ".npm-cache").path,
                    ])
                #expect(command.environment == environment)
                #expect(command.timeout == .seconds(300))
                #expect(try Data(contentsOf: stage.appending(path: "package.json")) == manifest)
                #expect(try Data(contentsOf: stage.appending(path: "package-lock.json")) == lock)
                try writeEntry(stage)
                if linked {
                    try FileManager.default.createSymbolicLink(
                        at: stage.appending(path: "entry.js"), withDestinationURL: stage.appending(path: entry))
                }
            }, at: destination, entryPoint: linked ? "entry.js" : entry)
        #expect(command.executable == "node")
        #expect(command.arguments == [destination.appending(path: entry).path, "--stdio", "literal space"])
        var expected = environment
        expected["PATH"] = destination.appending(path: "node_modules/.bin").path + ":/usr/bin:/bin"
        #expect(command.environment == expected)
        #expect(command.workingDirectory == destination.deletingLastPathComponent())
        #expect(try Data(contentsOf: destination.appending(path: "package.json")) == manifest)
        #expect(try Data(contentsOf: destination.appending(path: "package-lock.json")) == lock)
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.path) == [destination.lastPathComponent])
    }

    @Test(arguments: [
        "cancel", "late-cancel", "timeout", "package.json", "package-lock.json", "missing", "escape",
        "directory",
    ])
    func failuresCleanStaging(_ mode: String) async throws {
        let root = try scratch()
        defer { try? FileManager.default.removeItem(at: root) }
        let outside = root.appending(path: "outside.js")
        try manifest.write(to: outside)
        let runner = Runner { command in
            let stage = URL(filePath: try #require(command.directory))
            switch mode {
            case "cancel": throw CancellationError()
            case "late-cancel": withUnsafeCurrentTask { $0?.cancel() }
            case "timeout": throw CommandError.timedOut("npm", after: .seconds(300))
            case "package.json", "package-lock.json": try Data("changed".utf8).write(to: stage.appending(path: mode))
            case "escape":
                try FileManager.default.createSymbolicLink(
                    at: stage.appending(path: "bad"), withDestinationURL: outside)
            case "directory":
                try FileManager.default.createDirectory(
                    at: stage.appending(path: "bad"), withIntermediateDirectories: false)
            default: break
            }
        }
        let task = Task { try await install(runner, at: root.appending(path: "install"), entryPoint: "bad") }
        switch mode {
        case "cancel", "late-cancel": await #expect(throws: CancellationError.self) { try await task.value }
        case "timeout":
            await #expect(throws: CommandError.timedOut("npm", after: .seconds(300))) { try await task.value }
        case "package.json", "package-lock.json":
            await #expect(throws: Failure.lockPairChanged) { try await task.value }
        default: await #expect(throws: Failure.invalidEntryPoint) { try await task.value }
        }
        #expect(try Data(contentsOf: outside) == manifest)
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.path) == ["outside.js"])
    }

    @Test(arguments: ["/absolute.js", "../escape.js", "a/../escape.js", "", "a\0b"])
    func rejectsUnsafePaths(_ path: String) async throws {
        let root = try scratch()
        defer { try? FileManager.default.removeItem(at: root) }
        await #expect(throws: Failure.invalidEntryPoint) {
            try await install(
                Runner { _ in Issue.record("npm must not run") }, at: root.appending(path: "install"), entryPoint: path)
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.path).isEmpty)
    }

    @Test(arguments: [false, true], ["directory", "file", "symlink"])
    func preservesDestination(_ race: Bool, _ kind: String) async throws {
        let root = try scratch()
        defer { try? FileManager.default.removeItem(at: root) }
        let destination = root.appending(path: "install")
        let occupy: @Sendable () throws -> Void = {
            switch kind {
            case "file": try manifest.write(to: destination)
            case "symlink":
                try FileManager.default.createSymbolicLink(atPath: destination.path, withDestinationPath: "absent")
            default: try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: false)
            }
        }
        if !race { try occupy() }
        await #expect(throws: Failure.destinationExists) {
            try await install(
                Runner { command in
                    #expect(race)
                    try writeEntry(URL(filePath: try #require(command.directory)))
                    try occupy()
                }, at: destination)
        }
        switch kind {
        case "file": #expect(try Data(contentsOf: destination) == manifest)
        case "symlink": #expect(try FileManager.default.destinationOfSymbolicLink(atPath: destination.path) == "absent")
        default: #expect(try FileManager.default.contentsOfDirectory(atPath: destination.path).isEmpty)
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.path) == ["install"])
    }

    @Test func policyRefusal() async throws {
        let root = try scratch()
        defer { try? FileManager.default.removeItem(at: root) }
        await #expect(throws: Failure.prohibitedByPolicy) {
            try await ManagedAdapterInstaller(runner: Runner { _ in Issue.record("npm must not run") }).install(
                auditedPackageJSON: manifest, auditedPackageLock: lock, destination: root.appending(path: "install"),
                entryPoint: entry, environment: environment, allowedByPolicy: false)
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.path).isEmpty)
    }

    @Test(arguments: [0, 23])
    func localSubprocess(_ exitCode: Int) async throws {
        let root = try scratch()
        defer { try? FileManager.default.removeItem(at: root) }
        let npm = root.appending(path: "npm")
        try Data(
            """
            #!/bin/sh
            set -eu
            test "$1" = ci && test "$2" = --ignore-scripts
            test "$7" = "$PWD" && test "$9" = "$PWD/.npm-cache"
            mkdir -p node_modules/fixture
            printf 'throw new Error("must never launch");' > node_modules/fixture/main.js
            exit \(exitCode)
            """.utf8
        ).write(to: npm)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: npm.path)
        let destination = root.appending(path: "install")
        let installer = ManagedAdapterInstaller(runner: LocalCommandRunner())
        let operation = {
            try await installer.install(
                auditedPackageJSON: manifest, auditedPackageLock: lock, destination: destination, entryPoint: entry,
                environment: ["PATH": root.path + ":/usr/bin:/bin", "HOME": root.path], allowedByPolicy: true)
        }
        if exitCode == 0 {
            let command = try await operation()
            #expect(FileManager.default.fileExists(atPath: try #require(command.arguments.first)))
        } else {
            await #expect(throws: Failure.npmFailed(23)) { try await operation() }
            #expect(try FileManager.default.contentsOfDirectory(atPath: root.path) == ["npm"])
        }
    }
}
