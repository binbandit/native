import Foundation
import NativeHostProtocol
import Synchronization

@testable import NativeLink

final class LinkIdentityMigrationFixture {
    let directory: URL
    let reference = KeychainLinkKeyStore.Reference(hostID: HostID(), channel: "migration-test")
    let secrets = LinkIdentityTestSecrets()
    let canary = Data("native-secret-canary-0123456789a".utf8)

    init() throws {
        // Foundation can normalize the system temporary path back through the /var symlink.
        directory = URL(filePath: "/private/tmp", directoryHint: .isDirectory)
            .appending(path: "link-migration-\(UUID())", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
    }

    deinit {
        try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        try? FileManager.default.removeItem(at: directory)
    }

    var keyURL: URL { directory.appending(path: LinkIdentityFiles.legacyName) }
    var recordURL: URL { directory.appending(path: LinkIdentityFiles.recordName) }

    func store(restricted: Bool = true, directory: URL? = nil) -> LinkIdentityMigration {
        LinkIdentityMigration(
            directory: directory ?? self.directory, restricted: restricted, reference: reference, secrets: secrets)
    }

    @discardableResult
    func legacy(_ data: Data? = nil) throws -> LinkIdentity {
        let data = data ?? canary
        try write(data, to: keyURL)
        return try LinkIdentity(rawRepresentation: data)
    }

    func write(_ data: Data, to url: URL) throws {
        try data.write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    func record() throws -> LinkIdentityMigration.Record {
        try JSONDecoder().decode(LinkIdentityMigration.Record.self, from: Data(contentsOf: recordURL))
    }
}

final class LinkIdentityTestSecrets: LinkIdentitySecretStore {
    struct State {
        var data: Data?
        var reads = 0
        var inserts = 0
        var readFailure: (Int, LinkIdentityStorageFailure)?
        var insertFailure: LinkIdentityStorageFailure?
        var substituteOnInsert: Data?
        var discardInsert = false
        var untrustedError: (any Error)?
    }

    let state = Mutex(State())

    func read() throws -> Data? {
        try state.withLock {
            $0.reads += 1
            if let error = $0.untrustedError { throw error }
            if let (at, error) = $0.readFailure, at == $0.reads { throw error }
            return $0.data
        }
    }

    func insert(_ data: Data) throws {
        try state.withLock {
            $0.inserts += 1
            if let failure = $0.insertFailure { throw failure }
            if !$0.discardInsert, $0.data == nil { $0.data = $0.substituteOnInsert ?? data }
        }
    }
}
