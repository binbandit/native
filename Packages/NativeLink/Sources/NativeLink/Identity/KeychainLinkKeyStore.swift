import Foundation
import LocalAuthentication
import NativeHostProtocol
import Security

/// The single item that holds a host's companion identity. Implementations insert without ever
/// replacing an existing identity.
protocol LinkIdentitySecretStore: Sendable {
    func read() throws -> Data?
    func insert(_ data: Data) throws
}

/// The host's companion identity in the Keychain: one generic password on this device only, under a
/// service of Native's own. Only `LinkIdentityMigration` reads it, so receipts and legacy files are
/// always checked first.
struct KeychainLinkKeyStore: LinkIdentitySecretStore {
    /// The exact item, derived from the host's own ID and channel. A migration receipt stores a copy
    /// to check against, but a query is never built from what a receipt says.
    struct Reference: Codable, Equatable, Sendable {
        let service: String
        let account: String

        init(hostID: HostID, channel: String) {
            // Its own service: `HostKeychain` decodes every item under "Native Host" as a credential.
            service = channel.isEmpty ? "Native Host Link Identity" : "Native Host Link Identity (\(channel))"
            account = hostID.description
        }
    }

    let reference: Reference

    func read() throws -> Data? {
        var result: CFTypeRef?
        let status = SecItemCopyMatching(
            query([kSecMatchLimit: kSecMatchLimitOne, kSecReturnData: true]) as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        try Self.check(status)
        guard let data = result as? Data else { throw LinkIdentityStorageFailure.invalidKey }
        return data
    }

    func insert(_ data: Data) throws {
        _ = try Self.decode(data)
        let status = SecItemAdd(
            query([
                kSecValueData: data,
                kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            ]) as CFDictionary, nil)
        // Another writer may have inserted an identity first; the migration reads it back and compares.
        if status == errSecDuplicateItem { return }
        try Self.check(status)
    }

    /// The Data Protection keychain, because it is the one that honors a context without interaction:
    /// the login keychain can show an unlock or access dialog, and a host nobody sits at would wait on
    /// it forever. It needs a keychain access group entitlement; without one every call fails with
    /// `keychainEntitlementMissing`, and the gateway stays off.
    func query(_ extra: [CFString: Any]) -> [CFString: Any] {
        let context = LAContext()
        context.interactionNotAllowed = true
        return [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: reference.service,
            kSecAttrAccount: reference.account,
            kSecAttrSynchronizable: false,
            kSecUseDataProtectionKeychain: true,
            kSecUseAuthenticationContext: context,
        ].merging(extra) { $1 }
    }

    static func decode(_ data: Data) throws -> LinkIdentity {
        do { return try LinkIdentity(rawRepresentation: data) } catch { throw LinkIdentityStorageFailure.invalidKey }
    }

    static func check(_ status: OSStatus) throws {
        switch status {
        case errSecSuccess: return
        case errSecInteractionNotAllowed: throw LinkIdentityStorageFailure.keychainLocked
        case errSecAuthFailed, errSecUserCanceled: throw LinkIdentityStorageFailure.keychainDenied
        case errSecMissingEntitlement: throw LinkIdentityStorageFailure.keychainEntitlementMissing
        default: throw LinkIdentityStorageFailure.keychainUnavailable
        }
    }
}
