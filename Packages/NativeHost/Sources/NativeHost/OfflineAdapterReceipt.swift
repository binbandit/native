import ACP
import Foundation
import NativeHostProtocol

/// A verified installation handle. Keep `sha256` in a trusted Native/deployment store for reuse.
public struct OfflineAdapterReceipt: Sendable {
    public let sha256: String
    public let command: AgentCommand

    struct Record: Codable, Equatable {
        let formatVersion: Int
        let manifestSHA256: String
        let nodeSHA256: String
        let npmCLISHA256: String
        let files: [OfflineAdapterBundle.Payload]
    }

    static func record(
        files: [String: Data], approval: OfflineAdapterBundle.Approval
    ) throws -> Data {
        let record = Record(
            formatVersion: 1, manifestSHA256: approval.manifestSHA256,
            nodeSHA256: approval.nodeSHA256, npmCLISHA256: approval.npmCLISHA256,
            files: try files.keys.sorted().map {
                try OfflineAdapterBundle.Payload(path: $0, bytes: files[$0] ?? Data())
            })
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(record)
    }

    /// No process, repair or network operation. A corrupt receipt or install fails in place.
    public static func reuse(
        at destination: URL, expectedSHA256: String, approval: OfflineAdapterBundle.Approval,
        localInstallAllowed: Bool, arguments: [String] = [], environment: [String: String] = [:],
        workingDirectory: URL? = nil
    ) throws -> Self {
        guard localInstallAllowed else { throw OfflineAdapterBundle.Failure.prohibitedByPolicy }
        try Task.checkCancellation()
        do {
            var files = try OfflineAdapterBundle.snapshot(destination)
            guard let receipt = files.removeValue(forKey: "receipt.json"),
                try ContentHash.sha256(receipt) == expectedSHA256,
                receipt == (try record(files: files, approval: approval)),
                let manifest = files["bundle.json"],
                try ContentHash.sha256(manifest) == approval.manifestSHA256,
                try approval.lock.matches(files)
            else { throw OfflineAdapterBundle.Failure.invalidReceipt }
            let bundle = try JSONDecoder().decode(OfflineAdapterBundle.self, from: manifest)
            guard bundle.formatVersion == 1, bundle.adapterID == approval.lock.adapterID,
                bundle.adapterVersion == approval.lock.adapterVersion, bundle.os == OfflineAdapterBundle.platformOS,
                bundle.architecture == OfflineAdapterBundle.platformArchitecture,
                bundle.nodeVersion == approval.nodeVersion, bundle.npmVersion == approval.npmVersion,
                bundle.agentVersion == approval.agentVersion
            else { throw OfflineAdapterBundle.Failure.qualificationMismatch }
            try requireInstalledFiles(bundle, files: files)
            try OfflineAdapterBundle.validateTools(approval)
            try Task.checkCancellation()
            return Self(
                sha256: expectedSHA256,
                command: command(
                    bundle, at: destination, approval: approval, arguments: arguments,
                    environment: environment, workingDirectory: workingDirectory))
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw OfflineAdapterBundle.Failure.invalidReceipt
        }
    }

    static func requireInstalledFiles(_ bundle: OfflineAdapterBundle, files: [String: Data]) throws {
        guard bundle.requiredInstalledFiles.allSatisfy({ files[$0] != nil }) else {
            throw OfflineAdapterBundle.Failure.missingArtifact
        }
    }

    static func command(
        _ bundle: OfflineAdapterBundle, at destination: URL, approval: OfflineAdapterBundle.Approval,
        arguments: [String], environment: [String: String], workingDirectory: URL?
    ) -> AgentCommand {
        AgentCommand(
            executable: approval.node.path,
            arguments: [destination.appending(path: bundle.entryPoint).path] + arguments,
            environment: environment, workingDirectory: workingDirectory)
    }
}
