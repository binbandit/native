import Darwin
import Foundation
import LocalAuthentication
import NativeHostProtocol
import Security
import Testing

@testable import NativeLink

@Suite struct LinkIdentityMigrationTests {
    @Test func newIdentityNeverWritesPrivateMaterialToDisk() throws {
        let fixture = try LinkIdentityMigrationFixture()
        let identity = try fixture.store().identity()
        #expect(!FileManager.default.fileExists(atPath: fixture.keyURL.path))
        #expect(try fixture.record().phase == .complete)
        #expect(try fixture.store().identity().publicKey == identity.publicKey)
        #expect(fixture.secrets.state.withLock { $0.inserts } == 1)
        let files = try FileManager.default.contentsOfDirectory(atPath: fixture.directory.path)
        #expect(files == [LinkIdentityFiles.recordName])
        let receipt = try Data(contentsOf: fixture.recordURL)
        #expect(receipt.range(of: identity.rawRepresentation) == nil)
        #expect(!String(decoding: receipt, as: UTF8.self).contains(identity.rawRepresentation.base64EncodedString()))
    }

    @Test func migrationPreservesIdentityAndDoesNotTouchGrants() throws {
        let fixture = try LinkIdentityMigrationFixture()
        let legacy = try fixture.legacy()
        let grantsURL = fixture.directory.appending(path: "devices.json")
        let grants = Data("unread-device-grants-fixture".utf8)
        try fixture.write(grants, to: grantsURL)
        #expect(try fixture.store().identity().publicKey == legacy.publicKey)
        #expect(try Data(contentsOf: grantsURL) == grants)
        #expect(!FileManager.default.fileExists(atPath: fixture.keyURL.path))
        #expect(try fixture.record().phase == .complete)
        #expect(fixture.secrets.state.withLock { $0.data } == fixture.canary)
        let receipt = try String(contentsOf: fixture.recordURL, encoding: .utf8)
        #expect(!receipt.contains(String(decoding: fixture.canary, as: UTF8.self)))
        #expect(!receipt.contains(fixture.canary.base64EncodedString()))
        let fields = try #require(JSONSerialization.jsonObject(with: Data(receipt.utf8)) as? [String: Any])
        #expect(Set(fields.keys) == ["version", "reference", "phase"])
    }

    @Test(arguments: [true, false]) func existingItemIsNeverReplaced(matching: Bool) throws {
        let fixture = try LinkIdentityMigrationFixture()
        let legacy = try fixture.legacy()
        let existing = matching ? legacy : LinkIdentity()
        fixture.secrets.state.withLock { $0.data = existing.rawRepresentation }
        if matching {
            #expect(try fixture.store().identity().publicKey == legacy.publicKey)
        } else {
            #expect(throws: LinkIdentityStorageFailure.conflictingIdentity) { try fixture.store().identity() }
            #expect(try Data(contentsOf: fixture.keyURL) == fixture.canary)
        }
        #expect(fixture.secrets.state.withLock { $0.inserts } == 0)
        #expect(fixture.secrets.state.withLock { $0.data } == existing.rawRepresentation)
    }

    @Test func existingItemWithoutLegacyIsRetained() throws {
        let fixture = try LinkIdentityMigrationFixture()
        let identity = LinkIdentity()
        fixture.secrets.state.withLock { $0.data = identity.rawRepresentation }
        #expect(try fixture.store().identity().publicKey == identity.publicKey)
        #expect(fixture.secrets.state.withLock { $0.inserts } == 0)
    }

    @Test(arguments: LinkIdentityMigration.Checkpoint.allCases, [true, false])
    func everyInterruptionResumesWithoutChangingIdentity(
        point: LinkIdentityMigration.Checkpoint, hasLegacy: Bool
    ) throws {
        let fixture = try LinkIdentityMigrationFixture()
        let legacy = hasLegacy ? try fixture.legacy() : nil
        var interrupted = fixture.store()
        interrupted.checkpoint = { if $0 == point { throw LinkIdentityStorageFailure.interrupted } }
        #expect(throws: (any Error).self) { try interrupted.identity() }
        let inserted = fixture.secrets.state.withLock { $0.data }
        // A receipt makes selection sticky even when the administrator changes policy modes.
        let resumed = try fixture.store(restricted: point == .prepare).identity()
        if let legacy { #expect(resumed.publicKey == legacy.publicKey) }
        if let inserted { #expect(resumed.publicKey == (try LinkIdentity(rawRepresentation: inserted)).publicKey) }
        #expect(try fixture.record().phase == .complete)
        #expect(!FileManager.default.fileExists(atPath: fixture.keyURL.path))
        #expect(try fixture.store(restricted: false).identity().publicKey == resumed.publicKey)
    }

    @Test(arguments: [LinkIdentityStorageFailure.keychainLocked, .keychainDenied, .keychainUnavailable], [1, 2])
    func keychainReadFailureBlocksWithoutFallback(error: LinkIdentityStorageFailure, read: Int) throws {
        let fixture = try LinkIdentityMigrationFixture()
        let legacy = try fixture.legacy()
        fixture.secrets.state.withLock { $0.readFailure = (read, error) }
        #expect(throws: error) { try fixture.store().identity() }
        #expect(try Data(contentsOf: fixture.keyURL) == fixture.canary)
        #expect(try fixture.record().phase == .importing)
        #expect(try fixture.store().identity().publicKey == legacy.publicKey)
    }

    @Test func failedInsertAndFailedReadBackKeepLegacy() throws {
        let fixture = try LinkIdentityMigrationFixture()
        try fixture.legacy()
        fixture.secrets.state.withLock { $0.insertFailure = .keychainDenied }
        #expect(throws: LinkIdentityStorageFailure.keychainDenied) { try fixture.store().identity() }
        fixture.secrets.state.withLock {
            $0.insertFailure = nil
            $0.discardInsert = true
        }
        #expect(throws: LinkIdentityStorageFailure.identityMissing) { try fixture.store().identity() }
        fixture.secrets.state.withLock {
            $0.discardInsert = false
            $0.substituteOnInsert = LinkIdentity().rawRepresentation
        }
        #expect(throws: LinkIdentityStorageFailure.conflictingIdentity) { try fixture.store().identity() }
        #expect(try Data(contentsOf: fixture.keyURL) == fixture.canary)
        #expect(try fixture.record().phase == .importing)
    }

    @Test func deletionFailureBlocksAndVerifiedKeyWinsOverStaleFile() throws {
        let fixture = try LinkIdentityMigrationFixture()
        let identity = try fixture.legacy()
        var store = fixture.store()
        let directory = fixture.directory
        store.checkpoint = { point in
            if point == .remove {
                try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: directory.path)
            }
        }
        #expect(throws: LinkIdentityStorageFailure.legacyRemovalFailed) { try store.identity() }
        #expect(try fixture.record().phase == .verified)
        #expect(try Data(contentsOf: fixture.keyURL) == fixture.canary)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        try fixture.legacy(LinkIdentity().rawRepresentation)
        #expect(try fixture.store(restricted: false).identity().publicKey == identity.publicKey)
        #expect(fixture.secrets.state.withLock { $0.inserts } == 1)
        #expect(!FileManager.default.fileExists(atPath: fixture.keyURL.path))
    }

    @Test(arguments: [LinkIdentityMigration.Checkpoint.verify, .complete])
    func receiptWriteFailureBlocksAndRestarts(point: LinkIdentityMigration.Checkpoint) throws {
        let fixture = try LinkIdentityMigrationFixture()
        let identity = try fixture.legacy()
        var store = fixture.store()
        let directory = fixture.directory
        store.checkpoint = {
            if $0 == point {
                try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: directory.path)
            }
        }
        #expect(throws: LinkIdentityStorageFailure.migrationWriteFailed) { try store.identity() }
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        #expect(try fixture.store().identity().publicKey == identity.publicKey)
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path) == [LinkIdentityFiles.recordName])
    }

    @Test func migratedRestartReadsOnlyKeychainAndReceipt() throws {
        let fixture = try LinkIdentityMigrationFixture()
        let identity = try fixture.store().identity()
        fixture.secrets.state.withLock { $0.reads = 0 }
        #expect(try fixture.store(restricted: false).identity().publicKey == identity.publicKey)
        #expect(fixture.secrets.state.withLock { $0.reads } == 1)
        // A returned raw copy is detected without opening it (a FIFO would block a raw reader).
        #expect(mkfifo(fixture.keyURL.path, 0o600) == 0)
        #expect(throws: LinkIdentityStorageFailure.legacyCopyPresent) {
            try fixture.store(restricted: false).identity()
        }
        fixture.secrets.state.withLock { $0.data = nil }
        #expect(throws: LinkIdentityStorageFailure.identityMissing) { try fixture.store(restricted: false).identity() }
        #expect(fixture.secrets.state.withLock { $0.inserts } == 1)
    }

    @Test(arguments: [0, 31, 33]) func corruptLegacyBlocksWithoutInsertion(count: Int) throws {
        let fixture = try LinkIdentityMigrationFixture()
        let data = Data(repeating: 0x61, count: count)
        try fixture.write(data, to: fixture.keyURL)
        #expect(throws: (any Error).self) { try fixture.store().identity() }
        #expect(fixture.secrets.state.withLock { $0.inserts } == 0)
        #expect(try Data(contentsOf: fixture.keyURL) == data)
        #expect(!FileManager.default.fileExists(atPath: fixture.recordURL.path))
    }

    @Test func invalidKeychainMaterialIsNotReplaced() throws {
        let fixture = try LinkIdentityMigrationFixture()
        fixture.secrets.state.withLock { $0.data = Data("invalid-canary".utf8) }
        #expect(throws: LinkIdentityStorageFailure.invalidKey) { try fixture.store().identity() }
        #expect(fixture.secrets.state.withLock { $0.inserts } == 0)
    }

    @Test(arguments: [LinkIdentityFiles.legacyName, LinkIdentityFiles.recordName])
    func symlinkFilesAreRefused(name: String) throws {
        let fixture = try LinkIdentityMigrationFixture()
        let target = fixture.directory.appending(path: "target")
        try fixture.write(fixture.canary, to: target)
        try FileManager.default.createSymbolicLink(
            at: fixture.directory.appending(path: name), withDestinationURL: target)
        #expect(throws: LinkIdentityStorageFailure.unsafePath) { try fixture.store().identity() }
        #expect(try Data(contentsOf: target) == fixture.canary)
        #expect(fixture.secrets.state.withLock { $0.reads } == 0)
    }

    @Test func symlinkDirectoryAndPathEscapeAreRefused() throws {
        let fixture = try LinkIdentityMigrationFixture()
        let alias = fixture.directory.appending(path: "alias")
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: fixture.directory)
        for directory in [alias, alias.appending(path: "Link"), fixture.directory.appending(path: "../escape")] {
            #expect(throws: LinkIdentityStorageFailure.unsafePath) {
                try fixture.store(directory: directory).identity()
            }
        }
        #expect(fixture.secrets.state.withLock { $0.reads } == 0)
    }

    @Test func nonPrivateOrHardlinkedFileIsRefused() throws {
        let fixture = try LinkIdentityMigrationFixture()
        try fixture.legacy()
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: fixture.keyURL.path)
        #expect(throws: LinkIdentityStorageFailure.unsafePath) { try fixture.store().identity() }
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fixture.keyURL.path)
        try FileManager.default.linkItem(at: fixture.keyURL, to: fixture.directory.appending(path: "copy"))
        #expect(throws: LinkIdentityStorageFailure.unsafePath) { try fixture.store().identity() }
        #expect(fixture.secrets.state.withLock { $0.reads } == 0)
    }

    /// "everyone" in ACL text: mode bits stay private while the ACL lets another user in.
    static let everyone = "group:ABCDEFAB-CDEF-ABCD-EFAB-CDEF0000000C:everyone:12"

    @Test func aclGrantsOnPrivateObjectsAreRefused() throws {
        let fixture = try LinkIdentityMigrationFixture()
        try fixture.legacy()
        try LinkIdentityMigrationFixture.setACL(["\(Self.everyone):allow:read"], on: fixture.keyURL)
        #expect(throws: LinkIdentityStorageFailure.unsafePath) { try fixture.store().identity() }
        try LinkIdentityMigrationFixture.setACL(nil, on: fixture.keyURL)
        let identity = try fixture.store().identity()

        try LinkIdentityMigrationFixture.setACL(["\(Self.everyone):allow:write"], on: fixture.recordURL)
        #expect(throws: LinkIdentityStorageFailure.unsafePath) { try fixture.store().identity() }
        try LinkIdentityMigrationFixture.setACL(nil, on: fixture.recordURL)
        // An inheritable grant on the Link folder would reach every receipt written into it.
        try LinkIdentityMigrationFixture.setACL(
            ["\(Self.everyone):allow,file_inherit:read,execute"], on: fixture.directory)
        #expect(throws: LinkIdentityStorageFailure.unsafePath) { try fixture.store().identity() }
        try LinkIdentityMigrationFixture.setACL(nil, on: fixture.directory)
        #expect(try fixture.store().identity().publicKey == identity.publicKey)
    }

    @Test func ancestorAclsRefuseOnlyGrantsThatReplaceEntries() throws {
        let fixture = try LinkIdentityMigrationFixture()
        let link = fixture.directory.appending(path: "Link", directoryHint: .isDirectory)
        // ACL text names directory rights by their file counterparts: append is add_subdirectory.
        try LinkIdentityMigrationFixture.setACL(["\(Self.everyone):allow:append"], on: fixture.directory)
        #expect(throws: LinkIdentityStorageFailure.unsafePath) { try fixture.store(directory: link).identity() }
        // Like the defaults on a home folder: denials and read-only grants change nothing here.
        try LinkIdentityMigrationFixture.setACL(
            ["\(Self.everyone):deny:delete", "\(Self.everyone):allow:read,execute"], on: fixture.directory)
        _ = try fixture.store(directory: link).identity()
        #expect(fixture.secrets.state.withLock { $0.inserts } == 1)
    }

    @Test func malformedOrForeignReceiptCannotChooseASecretOwner() throws {
        let fixture = try LinkIdentityMigrationFixture()
        try fixture.write(Data("not-json-canary".utf8), to: fixture.recordURL)
        #expect(throws: LinkIdentityStorageFailure.invalidMigrationState) {
            try fixture.store(restricted: false).identity()
        }
        let foreign = KeychainLinkKeyStore.Reference(hostID: HostID(), channel: "other")
        let record = LinkIdentityMigration.Record(reference: foreign, phase: .complete)
        try fixture.write(JSONEncoder().encode(record), to: fixture.recordURL)
        #expect(throws: LinkIdentityStorageFailure.invalidMigrationState) { try fixture.store().identity() }
        #expect(fixture.secrets.state.withLock { $0.reads } == 0)
    }

    @Test func ordinaryUnmigratedHostKeepsItsFileIdentity() throws {
        let fixture = try LinkIdentityMigrationFixture()
        let first = try fixture.store(restricted: false).identity()
        #expect(try fixture.store(restricted: false).identity().publicKey == first.publicKey)
        #expect(FileManager.default.fileExists(atPath: fixture.keyURL.path))
        #expect(!FileManager.default.fileExists(atPath: fixture.recordURL.path))
        #expect(fixture.secrets.state.withLock { $0.reads + $0.inserts } == 0)
    }

    @Test func identityFailurePreventsGatewayConstruction() throws {
        let fixture = try LinkIdentityMigrationFixture()
        fixture.secrets.state.withLock { $0.readFailure = (1, .keychainLocked) }
        let configuration = LinkGateway.Configuration(
            directory: fixture.directory, hostID: HostID(), machineName: "Test")
        #expect(throws: LinkIdentityStorageFailure.keychainLocked) {
            try LinkGateway(configuration: configuration, keyStore: fixture.store(), accept: { _, _ in })
        }
        #expect(!FileManager.default.fileExists(atPath: configuration.controlSocketPath))
        #expect(!FileManager.default.fileExists(atPath: fixture.directory.appending(path: "devices.json").path))
    }

    @Test func errorSerializationContainsOnlyCodes() throws {
        let fixture = try LinkIdentityMigrationFixture()
        #expect(throws: LinkIdentityStorageFailure.keychainEntitlementMissing) {
            try KeychainLinkKeyStore.check(errSecMissingEntitlement)
        }
        for status in [errSecInteractionNotAllowed, errSecAuthFailed, errSecMissingEntitlement, errSecNotAvailable] {
            do {
                try KeychainLinkKeyStore.check(status)
                Issue.record("Expected a blocked Keychain status")
            } catch let error as LinkIdentityStorageFailure {
                let encoded = try JSONEncoder().encode(error)
                #expect(encoded.range(of: fixture.canary) == nil)
                #expect(!error.localizedDescription.contains(fixture.directory.path))
            }
        }
    }

    @Test func keychainQueryHasOneNativeOwnerAndCannotPrompt() throws {
        let host = HostID()
        let reference = KeychainLinkKeyStore.Reference(hostID: host, channel: "fixture")
        let query = KeychainLinkKeyStore(reference: reference).query([:])
        #expect(query[kSecAttrService] as? String == "Native Host Link Identity (fixture)")
        #expect(query[kSecAttrAccount] as? String == host.description)
        #expect(query[kSecAttrSynchronizable] as? Bool == false)
        // The login keychain ignores the context and can show a dialog nobody answers.
        #expect(query[kSecUseDataProtectionKeychain] as? Bool == true)
        #expect((query[kSecUseAuthenticationContext] as? LAContext)?.interactionNotAllowed == true)
        #expect(query[kSecAttrAccessGroup] == nil)
        #expect(query[kSecMatchLimit] == nil)
        #expect(KeychainLinkKeyStore.Reference(hostID: host, channel: "").service == "Native Host Link Identity")
        #expect(reference != KeychainLinkKeyStore.Reference(hostID: HostID(), channel: "fixture"))
    }

    @Test func underlyingErrorsCannotLeakCanaryContent() throws {
        let fixture = try LinkIdentityMigrationFixture()
        fixture.secrets.state.withLock {
            $0.untrustedError = NSError(
                domain: String(decoding: fixture.canary, as: UTF8.self), code: 1,
                userInfo: [NSLocalizedDescriptionKey: fixture.canary.base64EncodedString()])
        }
        do {
            _ = try fixture.store().identity()
            Issue.record("Expected storage failure")
        } catch let error as LinkIdentityStorageFailure {
            #expect(error == .keychainUnavailable)
            let serialized = String(decoding: try JSONEncoder().encode(error), as: UTF8.self)
            #expect(!serialized.contains(String(decoding: fixture.canary, as: UTF8.self)))
            #expect(!error.localizedDescription.contains(fixture.canary.base64EncodedString()))
        }
    }

    @Test func verifiedMissingItemNeverReimportsLegacy() throws {
        let fixture = try LinkIdentityMigrationFixture()
        try fixture.legacy()
        var store = fixture.store()
        store.checkpoint = { if $0 == .verified { throw LinkIdentityStorageFailure.interrupted } }
        #expect(throws: LinkIdentityStorageFailure.interrupted) { try store.identity() }
        fixture.secrets.state.withLock { $0.data = nil }
        #expect(throws: LinkIdentityStorageFailure.identityMissing) { try fixture.store(restricted: false).identity() }
        #expect(fixture.secrets.state.withLock { $0.inserts } == 1)
        #expect(try Data(contentsOf: fixture.keyURL) == fixture.canary)
    }

    @Test func missingImportSourceAndUnsafeDirectoryBlock() throws {
        let fixture = try LinkIdentityMigrationFixture()
        try fixture.legacy()
        var store = fixture.store()
        store.checkpoint = { if $0 == .prepared { throw LinkIdentityStorageFailure.interrupted } }
        #expect(throws: LinkIdentityStorageFailure.interrupted) { try store.identity() }
        try FileManager.default.removeItem(at: fixture.keyURL)
        #expect(throws: LinkIdentityStorageFailure.identityMissing) { try fixture.store().identity() }
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fixture.directory.path)
        #expect(throws: LinkIdentityStorageFailure.unsafePath) { try fixture.store().identity() }
        #expect(fixture.secrets.state.withLock { $0.reads + $0.inserts } == 0)
    }
}
