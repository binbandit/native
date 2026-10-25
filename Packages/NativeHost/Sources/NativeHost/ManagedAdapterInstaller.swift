import ACP
import Exec
import Foundation
import NativeHostProtocol

#if os(Linux)
import Glibc
#else
import Darwin
#endif

/// Installs an explicitly trusted, already-audited lock pair. This does not audit or launch adapters.
public struct ManagedAdapterInstaller: Sendable {
    public enum Failure: Error, Equatable {
        case prohibitedByPolicy, destinationExists, invalidEntryPoint, lockPairChanged
        case npmFailed(Int32)
    }

    private let runner: any CommandRunner

    /// The runner must execute on this host, against the same filesystem as the installer.
    public init(runner: any CommandRunner) { self.runner = runner }

    /// The caller owns the existing parent directory and must keep it stable during installation.
    /// `allowedByPolicy` is the caller's effective managed-policy decision for adapter downloads.
    public func install(
        auditedPackageJSON: Data, auditedPackageLock: Data, destination: URL, entryPoint: String,
        arguments: [String] = [], environment: [String: String], workingDirectory: URL? = nil,
        allowedByPolicy: Bool
    ) async throws -> AgentCommand {
        guard allowedByPolicy else { throw Failure.prohibitedByPolicy }
        try Task.checkCancellation()
        guard !entryPoint.isEmpty, !entryPoint.hasPrefix("/"), !entryPoint.contains("\0"),
            !entryPoint.split(separator: "/").contains("..")
        else { throw Failure.invalidEntryPoint }
        let files = FileManager.default
        let parent = destination.deletingLastPathComponent().resolvingSymlinksInPath()
        let final = parent.appending(path: destination.lastPathComponent)
        guard (try? files.attributesOfItem(atPath: final.path)) == nil else { throw Failure.destinationExists }
        let stage = parent.appending(path: ".adapter-install-\(UUID().uuidString)")
        guard mkdir(stage.path, 0o700) == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        defer { try? files.removeItem(at: stage) }
        // npm compares prefix and physical cwd. Foundation can shorten /private/var back to /var.
        guard let physical = realpath(stage.path, nil) else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        let installPath = String(cString: physical)
        free(physical)
        let pair = [("package.json", auditedPackageJSON), ("package-lock.json", auditedPackageLock)]
        for (name, bytes) in pair { try bytes.write(to: stage.appending(path: name)) }
        let result = try await runner.run(
            Command(
                "npm",
                [
                    "ci", "--ignore-scripts", "--no-audit", "--no-fund", "--global=false", "--prefix", installPath,
                    "--cache", installPath + "/.npm-cache", "--include=optional",
                ],
                in: installPath, environment: environment, timeout: .seconds(300)))
        try Task.checkCancellation()
        // npm's output can contain credentials. Only the exit status crosses this API.
        guard result.succeeded else { throw Failure.npmFailed(result.exitCode) }
        for (name, bytes) in pair {
            guard try Data(contentsOf: stage.appending(path: name)) == bytes else { throw Failure.lockPairChanged }
        }
        let entry = stage.appending(path: entryPoint).resolvingSymlinksInPath()
        guard entry.path.hasPrefix(stage.path + "/"),
            (try? entry.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
        else { throw Failure.invalidEntryPoint }
        // Return the resolved file so even an absolute link into staging survives publication.
        let installedEntry = final.appending(path: String(entry.path.dropFirst(stage.path.count + 1)))
        try Task.checkCancellation()
        try Self.publish(stage, to: final)
        var launchEnvironment = environment
        launchEnvironment["PATH"] = [final.appending(path: "node_modules/.bin").path, environment["PATH"]]
            .compactMap(\.self).joined(separator: ":")
        return AgentCommand(
            executable: "node", arguments: [installedEntry.path] + arguments,
            environment: launchEnvironment, workingDirectory: workingDirectory)
    }

    /// Explicit local-only import. The caller supplies the local-install policy decision separately
    /// from download permission. This path has no download fallback, even when downloads are allowed.
    public func importOffline(
        from source: URL, approval: OfflineAdapterBundle.Approval, destination: URL,
        localInstallAllowed: Bool, arguments: [String] = [], environment: [String: String] = [:],
        workingDirectory: URL? = nil
    ) async throws -> OfflineAdapterReceipt {
        guard localInstallAllowed else { throw OfflineAdapterBundle.Failure.prohibitedByPolicy }
        try Task.checkCancellation()
        let inputs = try OfflineAdapterBundle.snapshot(source)
        let bundle = try OfflineAdapterBundle.validate(inputs, approval: approval)
        try OfflineAdapterBundle.validateTools(approval)
        let files = FileManager.default
        guard destination.isFileURL, destination.path.hasPrefix("/"),
            OfflineAdapterBundle.validPath(destination.lastPathComponent)
        else { throw OfflineAdapterBundle.Failure.unsafeFiles }
        // The caller owns and stabilizes this private parent, as for the online installer.
        let parent = destination.deletingLastPathComponent()
        let parentDescriptor = try OfflineAdapterBundle.openDirectory(parent)
        defer { close(parentDescriptor) }
        var info = stat()
        guard fstat(parentDescriptor, &info) == 0, info.st_mode & S_IFMT == S_IFDIR,
            info.st_uid == geteuid(), info.st_mode & 0o077 == 0
        else { throw OfflineAdapterBundle.Failure.unsafeFiles }
        guard lstat(destination.path, &info) != 0, errno == ENOENT else { throw Failure.destinationExists }
        try Task.checkCancellation()
        let stage = parent.appending(path: ".adapter-install-\(UUID().uuidString)")
        guard mkdir(stage.path, 0o700) == 0 else { throw OfflineAdapterBundle.Failure.storageFailed }
        defer { try? files.removeItem(at: stage) }
        for (path, bytes) in inputs {
            let target = stage.appending(path: path)
            try files.createDirectory(
                at: target.deletingLastPathComponent(), withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700])
            try bytes.write(to: target, options: .withoutOverwriting)
            try files.setAttributes([.posixPermissions: 0o600], ofItemAtPath: target.path)
        }
        let configuration = stage.appending(path: ".configuration")
        try files.createDirectory(
            at: configuration, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        for name in ["user.npmrc", "global.npmrc"] {
            try Data().write(to: configuration.appending(path: name), options: .withoutOverwriting)
        }
        let installEnvironment = [
            "HOME": configuration.path, "PATH": approval.node.deletingLastPathComponent().path,
            "TMPDIR": configuration.path,
        ]
        let npmFlags = [
            "--offline", "--ignore-scripts", "--no-audit", "--no-fund", "--global=false",
            "--prefix", stage.path, "--cache", stage.appending(path: "cache").path,
            "--userconfig", configuration.appending(path: "user.npmrc").path,
            "--globalconfig", configuration.appending(path: "global.npmrc").path,
            "--include=optional", "--include=dev", "--include=peer", "--bin-links=false",
            "--update-notifier=false", "--logs-max=0", "--progress=false", "--fetch-retries=0",
        ]
        func run(_ arguments: [String]) async throws -> CommandResult {
            do {
                try Task.checkCancellation()
                return try await runner.run(
                    Command(
                        approval.node.path, arguments, in: stage.path,
                        environment: installEnvironment, timeout: .seconds(300)))
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                throw OfflineAdapterBundle.Failure.toolFailed
            }
        }
        let nodeVersion = try await run(["--version"])
        let npmVersion = try await run([approval.npmCLI.path, "--version"] + npmFlags)
        guard nodeVersion.succeeded, npmVersion.succeeded,
            nodeVersion.output.trimmingCharacters(in: .whitespacesAndNewlines) == "v" + bundle.nodeVersion,
            npmVersion.output.trimmingCharacters(in: .whitespacesAndNewlines) == bundle.npmVersion
        else { throw OfflineAdapterBundle.Failure.qualificationMismatch }
        let result = try await run([approval.npmCLI.path, "ci"] + npmFlags)
        try Task.checkCancellation()
        // npm output may contain registry material. No output or package name crosses this boundary.
        guard result.succeeded else { throw OfflineAdapterBundle.Failure.missingArtifact }
        try files.removeItem(at: configuration)
        if files.fileExists(atPath: stage.appending(path: "cache").path) {
            try files.removeItem(at: stage.appending(path: "cache"))
        }
        let installed = try OfflineAdapterBundle.snapshot(stage)
        guard installed["package.json"] == approval.packageJSON,
            installed["package-lock.json"] == approval.packageLock,
            installed["bundle.json"] == inputs["bundle.json"]
        else { throw Failure.lockPairChanged }
        try OfflineAdapterReceipt.requireInstalledFiles(bundle, files: installed)
        let receipt = try OfflineAdapterReceipt.record(files: installed, approval: approval)
        try receipt.write(to: stage.appending(path: "receipt.json"), options: .withoutOverwriting)
        try files.setAttributes([.posixPermissions: 0o600], ofItemAtPath: stage.appending(path: "receipt.json").path)
        let digest = try ContentHash.sha256(receipt)
        try Task.checkCancellation()
        try Self.publish(stage, to: destination)
        return OfflineAdapterReceipt(
            sha256: digest,
            command: OfflineAdapterReceipt.command(
                bundle, at: destination, approval: approval, arguments: arguments,
                environment: environment, workingDirectory: workingDirectory))
    }

    private static func publish(_ stage: URL, to destination: URL) throws {
        // Foundation's check-then-move can replace an empty directory in a destination race.
        #if os(Linux)
        typealias Rename = @convention(c) (Int32, UnsafePointer<CChar>, Int32, UnsafePointer<CChar>, UInt32) -> Int32
        guard let symbol = dlsym(nil, "renameat2") else { throw POSIXError(.ENOSYS) }
        let rename = unsafeBitCast(symbol, to: Rename.self)
        let result = rename(AT_FDCWD, stage.path, AT_FDCWD, destination.path, 1)  // RENAME_NOREPLACE
        #else
        let result = renamex_np(stage.path, destination.path, UInt32(RENAME_EXCL))
        #endif
        guard result == 0 else {
            let code = errno
            if code == EEXIST { throw Failure.destinationExists }
            throw POSIXError(POSIXErrorCode(rawValue: code) ?? .EIO)
        }
    }
}
