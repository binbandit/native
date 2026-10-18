import Foundation
import Security

/// Where a `LinkIdentity` lives between launches.
public protocol LinkKeyStore: Sendable {
    /// The stored identity, or a new one, stored first.
    func identity() throws -> LinkIdentity
}

/// A key file readable by the user alone, beside the host's socket and store. The host runs as a
/// launchd agent of a build that changes signature with every development build, so the keychain
/// would prompt; the host directory (0700) is already the boundary its socket relies on.
public struct FileKeyStore: LinkKeyStore {
    public let url: URL

    public init(url: URL) {
        self.url = url
    }

    public func identity() throws -> LinkIdentity {
        if let data = try? Data(contentsOf: url) {
            return try LinkIdentity(rawRepresentation: data)
        }
        let identity = LinkIdentity()
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700])
        // Created readable by the user alone, before the key is written into it.
        guard
            FileManager.default.createFile(
                atPath: url.path(percentEncoded: false), contents: identity.rawRepresentation,
                attributes: [.posixPermissions: 0o600])
        else {
            throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: url.path(percentEncoded: false)])
        }
        return identity
    }
}

/// The device's key in its keychain, kept on this device only (never synced or backed up to another).
public struct KeychainKeyStore: LinkKeyStore {
    public let service: String
    public let account: String

    public init(service: String, account: String = "device-identity") {
        self.service = service
        self.account = account
    }

    public func identity() throws -> LinkIdentity {
        var query = baseQuery
        query[kSecReturnData as String] = true
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecSuccess, let data = result as? Data {
            return try LinkIdentity(rawRepresentation: data)
        }
        guard status == errSecItemNotFound else { throw KeychainError(status: status) }
        let identity = LinkIdentity()
        var item = baseQuery
        item[kSecValueData as String] = identity.rawRepresentation
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let added = SecItemAdd(item as CFDictionary, nil)
        guard added == errSecSuccess else { throw KeychainError(status: added) }
        return identity
    }

    /// Forgets the key, so the next pairing starts from a new identity.
    public func remove() {
        SecItemDelete(baseQuery as CFDictionary)
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}

public struct KeychainError: Error, LocalizedError, Sendable {
    public let status: OSStatus

    public var errorDescription: String? {
        let message = SecCopyErrorMessageString(status, nil) as String? ?? "status \(status)"
        return "The keychain refused: \(message)"
    }
}

/// An identity held in memory, for tests and previews.
public struct MemoryKeyStore: LinkKeyStore {
    private let stored: LinkIdentity

    public init(_ identity: LinkIdentity = LinkIdentity()) {
        stored = identity
    }

    public func identity() throws -> LinkIdentity { stored }
}
