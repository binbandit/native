import Foundation
import Security
import Synchronization

/// Where managed servers' secret values live, keyed by server.
public protocol SecretStore: Sendable {
    func secrets(for server: UUID) throws -> ManagedServerSecrets?
    /// Replaces the server's secrets; empty secrets remove them.
    func setSecrets(_ secrets: ManagedServerSecrets, for server: UUID, label: String) throws
}

public struct SecretStoreError: Error, Hashable, Sendable, LocalizedError {
    public var status: OSStatus

    public var errorDescription: String? {
        (SecCopyErrorMessageString(status, nil) as String?) ?? "Keychain error \(status)."
    }
}

/// One generic-password item per server in the login keychain, holding its values as JSON.
public struct KeychainSecretStore: SecretStore {
    public var service: String

    public init(service: String = "Native MCP servers") {
        self.service = service
    }

    public func secrets(for server: UUID) throws -> ManagedServerSecrets? {
        var query = baseQuery(server)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw SecretStoreError(status: status) }
        return try JSONDecoder().decode(ManagedServerSecrets.self, from: data)
    }

    public func setSecrets(_ secrets: ManagedServerSecrets, for server: UUID, label: String) throws {
        let query = baseQuery(server)
        guard !secrets.isEmpty else {
            let status = SecItemDelete(query as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else { throw SecretStoreError(status: status) }
            return
        }
        let data = try JSONEncoder().encode(secrets)
        let attributes: [String: Any] = [kSecValueData as String: data, kSecAttrLabel as String: label]
        var status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            status = SecItemAdd(query.merging(attributes) { $1 } as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw SecretStoreError(status: status) }
    }

    private func baseQuery(_ server: UUID) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: server.uuidString,
        ]
    }
}

/// Secrets in memory, for tests and previews.
public final class MemorySecretStore: SecretStore {
    private let values = Mutex<[UUID: ManagedServerSecrets]>([:])

    public init() {}

    public func secrets(for server: UUID) throws -> ManagedServerSecrets? {
        values.withLock { $0[server] }
    }

    public func setSecrets(_ secrets: ManagedServerSecrets, for server: UUID, label: String) throws {
        values.withLock { $0[server] = secrets.isEmpty ? nil : secrets }
    }
}
