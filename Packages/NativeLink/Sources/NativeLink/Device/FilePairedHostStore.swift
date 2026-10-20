import Foundation
import NativeHostProtocol

/// Paired hosts as a Mac keeps them: one file per host (holding that pairing's private key) in a
/// folder readable by the user alone. The Mac app changes signature with every development build,
/// so the keychain would prompt on each one; the folder is the same boundary the host's own key
/// (`FileKeyStore`) and socket rely on. Unpairing one host deletes its file and touches nothing else.
public struct FilePairedHostStore: PairedHostStore {
    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    public func hosts() throws -> [PairedHost] {
        guard FileManager.default.fileExists(atPath: directory.path(percentEncoded: false)) else { return [] }
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        return
            files
            .filter { $0.pathExtension == "json" }
            .compactMap { try? Self.decoder.decode(PairedHost.self, from: Data(contentsOf: $0)) }
            .sorted { $0.pairedAt < $1.pairedAt }
    }

    public func save(_ host: PairedHost) throws {
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o700], ofItemAtPath: directory.path(percentEncoded: false))
        let url = file(host.hostID)
        // Written beside the file and renamed into place, readable by the user alone before the key
        // is in it, so a crash never leaves half a pairing or a readable key.
        let staging = directory.appending(path: ".\(host.hostID.description).\(UUID().uuidString)")
        guard
            FileManager.default.createFile(
                atPath: staging.path(percentEncoded: false), contents: try Self.encoder.encode(host),
                attributes: [.posixPermissions: 0o600])
        else {
            throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: url.path(percentEncoded: false)])
        }
        guard rename(staging.path(percentEncoded: false), url.path(percentEncoded: false)) == 0 else {
            let error = CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: url.path(percentEncoded: false)])
            try? FileManager.default.removeItem(at: staging)
            throw error
        }
    }

    public func remove(_ hostID: HostID) throws {
        do {
            try FileManager.default.removeItem(at: file(hostID))
        } catch CocoaError.fileNoSuchFile {
            return
        }
    }

    private func file(_ hostID: HostID) -> URL {
        directory.appending(path: "\(hostID.description).json")
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
