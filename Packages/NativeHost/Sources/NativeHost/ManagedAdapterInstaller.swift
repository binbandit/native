import ACP
import Exec
import Foundation

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
        let pair = [("package.json", auditedPackageJSON), ("package-lock.json", auditedPackageLock)]
        for (name, bytes) in pair { try bytes.write(to: stage.appending(path: name)) }
        let result = try await runner.run(
            Command(
                "npm",
                [
                    "ci", "--ignore-scripts", "--no-audit", "--no-fund", "--global=false", "--prefix", stage.path,
                    "--cache", stage.appending(path: ".npm-cache").path,
                ],
                in: stage.path, environment: environment, timeout: .seconds(300)))
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
