import Darwin
import Foundation
import NativeHostProtocol

/// Where a host keeps its companion identity. An ordinary host keeps `identity.key` beside its
/// paired devices (`FileKeyStore`). A restricted host moves it into the Keychain once,
/// crash-safely, and from then on a receipt (`identity-storage.json`, which holds no key material)
/// keeps it there, whatever mode the host runs in later. It never updates or deletes a keychain
/// item, and never falls back to a file or a new key when the keychain fails.
///
/// Only the host that holds its location's lock (`HostMain`) may use it, which keeps two migrations
/// of one directory from running at once. docs/enterprise/host-identity-storage.md has the
/// transaction and recovery steps.
public struct LinkIdentityMigration: LinkKeyStore {
    let directory: URL
    let restricted: Bool
    let reference: KeychainLinkKeyStore.Reference
    let secrets: any LinkIdentitySecretStore
    /// Tests interrupt the migration at each point to check that it resumes.
    var checkpoint: @Sendable (Checkpoint) throws -> Void = { _ in }

    /// `directory` is the gateway's (`LinkGateway.Configuration.directory`); `hostID` and `channel`
    /// name the keychain item, so each host and channel has its own.
    public init(directory: URL, hostID: HostID, channel: String, restricted: Bool) {
        let store = KeychainLinkKeyStore(reference: .init(hostID: hostID, channel: channel))
        self.init(directory: directory, restricted: restricted, reference: store.reference, secrets: store)
    }

    init(
        directory: URL, restricted: Bool, reference: KeychainLinkKeyStore.Reference,
        secrets: any LinkIdentitySecretStore
    ) {
        self.directory = directory
        self.restricted = restricted
        self.reference = reference
        self.secrets = secrets
    }

    public func identity() throws -> LinkIdentity {
        // An ordinary host that never migrated keeps today's file. lstat also sees a receipt that is
        // a broken symlink, which blocks below rather than falling back.
        if !restricted {
            var info = stat()
            let receipt = directory.appending(path: LinkIdentityFiles.recordName).path(percentEncoded: false)
            if lstat(receipt, &info) != 0 {
                guard errno == ENOENT else { throw LinkIdentityStorageFailure.unsafePath }
                return try FileKeyStore(url: directory.appending(path: LinkIdentityFiles.legacyName)).identity()
            }
        }
        let files = try LinkIdentityFiles(directory: directory)
        var record: Record
        if let saved = try loadRecord(files) {
            record = saved
        } else {
            let phase: Phase = try legacyIdentity(files) == nil ? .creating : .importing
            record = Record(reference: reference, phase: phase)
            try save(record, to: files, at: .prepare)
            try reach(.prepared)
        }
        switch record.phase {
        case .creating, .importing:
            return try migrate(&record, files: files)
        case .verified:
            // The keychain is authoritative from here: a missing item is a recovery problem, never
            // permission to import the old file again or make a new key.
            let identity = try requiredIdentity()
            try finish(&record, files: files)
            return identity
        case .complete:
            let identity = try requiredIdentity()
            // Checked without opening it: a raw copy that came back (a stale rollback, a restored
            // backup) means the key isn't keychain-only any more.
            guard try !files.exists(LinkIdentityFiles.legacyName) else {
                throw LinkIdentityStorageFailure.legacyCopyPresent
            }
            return identity
        }
    }

    /// Puts the legacy key (or a new one) in the keychain, reads it back, and only then removes the file.
    private func migrate(_ record: inout Record, files: LinkIdentityFiles) throws -> LinkIdentity {
        let legacy = try legacyIdentity(files)
        if record.phase == .importing, legacy == nil { throw LinkIdentityStorageFailure.identityMissing }
        if record.phase == .creating, legacy != nil { throw LinkIdentityStorageFailure.conflictingIdentity }
        let existing = try readSecret()
        // Paired devices trust one of them; choosing would unpair the others, so an administrator does.
        if let existing, let legacy, existing.publicKey != legacy.publicKey {
            throw LinkIdentityStorageFailure.conflictingIdentity
        }
        let identity = existing ?? legacy ?? LinkIdentity()
        if existing == nil {
            do { try secrets.insert(identity.rawRepresentation) } catch { throw sanitized(error) }
        }
        try reach(.inserted)
        let verified = try requiredIdentity()
        guard verified.publicKey == identity.publicKey else { throw LinkIdentityStorageFailure.conflictingIdentity }
        try reach(.readBack)
        record.phase = .verified
        try save(record, to: files, at: .verify)
        try reach(.verified)
        try finish(&record, files: files)
        return verified
    }

    private func finish(_ record: inout Record, files: LinkIdentityFiles) throws {
        do {
            try checkpoint(.remove)
            try files.removeLegacy()
        } catch { throw LinkIdentityStorageFailure.legacyRemovalFailed }
        try reach(.removed)
        record.phase = .complete
        try save(record, to: files, at: .complete)
        try reach(.completed)
    }

    private func loadRecord(_ files: LinkIdentityFiles) throws -> Record? {
        guard let data = try files.read(LinkIdentityFiles.recordName, limit: 4096) else { return nil }
        // A receipt naming another item can't redirect the reader: the reference comes from the host.
        guard let record = try? JSONDecoder().decode(Record.self, from: data), record.version == 1,
            record.reference == reference
        else { throw LinkIdentityStorageFailure.invalidMigrationState }
        return record
    }

    private func save(_ record: Record, to files: LinkIdentityFiles, at point: Checkpoint) throws {
        do {
            try checkpoint(point)
            try files.writeRecord(JSONEncoder().encode(record))
        } catch { throw LinkIdentityStorageFailure.migrationWriteFailed }
    }

    private func legacyIdentity(_ files: LinkIdentityFiles) throws -> LinkIdentity? {
        guard let data = try files.read(LinkIdentityFiles.legacyName, limit: 32) else { return nil }
        return try KeychainLinkKeyStore.decode(data)
    }

    private func readSecret() throws -> LinkIdentity? {
        do {
            guard let data = try secrets.read() else { return nil }
            return try KeychainLinkKeyStore.decode(data)
        } catch { throw sanitized(error) }
    }

    private func requiredIdentity() throws -> LinkIdentity {
        guard let identity = try readSecret() else { throw LinkIdentityStorageFailure.identityMissing }
        return identity
    }

    private func sanitized(_ error: any Error) -> LinkIdentityStorageFailure {
        error as? LinkIdentityStorageFailure ?? .keychainUnavailable
    }

    private func reach(_ point: Checkpoint) throws {
        do { try checkpoint(point) } catch { throw LinkIdentityStorageFailure.interrupted }
    }

    enum Checkpoint: CaseIterable, Sendable {
        case prepare, prepared, inserted, readBack, verify, verified, remove, removed, complete, completed
    }

    struct Record: Codable {
        var version = 1
        let reference: KeychainLinkKeyStore.Reference
        var phase: Phase
    }

    enum Phase: String, Codable { case creating, importing, verified, complete }
}

/// Why the companion identity is unavailable. Only these codes leave the store: never key bytes,
/// file contents or paths.
public enum LinkIdentityStorageFailure: String, Error, LocalizedError, Codable, Sendable {
    /// Locked, or access would have needed someone to answer a prompt.
    case keychainLocked
    case keychainDenied
    /// The host isn't signed with the keychain access group the Data Protection keychain needs.
    case keychainEntitlementMissing
    case keychainUnavailable
    case identityMissing
    case invalidKey
    /// The keychain and the legacy file hold different identities.
    case conflictingIdentity
    case unsafePath
    case invalidMigrationState
    case migrationWriteFailed
    case legacyRemovalFailed
    /// A raw key file reappeared after the migration completed.
    case legacyCopyPresent
    case interrupted

    public var errorDescription: String? { "Companion identity unavailable (\(rawValue))." }
}
