import Foundation
import NativeHostProtocol
import Security
import Synchronization

/// Where a device keeps its paired hosts: one keychain item per host (holding that pairing's private
/// key), available after first unlock and never leaving this device. Unpairing one host deletes its
/// item and touches nothing else.
public protocol PairedHostStore: Sendable {
    func hosts() throws -> [PairedHost]
    func save(_ host: PairedHost) throws
    func remove(_ hostID: HostID) throws
}

public struct KeychainPairedHostStore: PairedHostStore {
    public let service: String

    public init(service: String) {
        self.service = service
    }

    public func hosts() throws -> [PairedHost] {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecMatchLimit as String: kSecMatchLimitAll,
            kSecReturnData as String: true,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return [] }
        guard status == errSecSuccess, let items = result as? [Data] else { throw KeychainError(status: status) }
        return items.compactMap { try? JSONDecoder().decode(PairedHost.self, from: $0) }.sorted {
            $0.pairedAt < $1.pairedAt
        }
    }

    public func save(_ host: PairedHost) throws {
        let data = try JSONEncoder().encode(host)
        let match = itemQuery(host.hostID)
        let updated = SecItemUpdate(match as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if updated == errSecSuccess { return }
        guard updated == errSecItemNotFound else { throw KeychainError(status: updated) }
        var item = match
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let added = SecItemAdd(item as CFDictionary, nil)
        guard added == errSecSuccess else { throw KeychainError(status: added) }
    }

    public func remove(_ hostID: HostID) throws {
        let status = SecItemDelete(itemQuery(hostID) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw KeychainError(status: status) }
    }

    private func itemQuery(_ hostID: HostID) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: hostID.description,
        ]
    }
}

/// Paired hosts in memory, for tests and previews.
public final class MemoryPairedHostStore: PairedHostStore {
    private let stored: Mutex<[HostID: PairedHost]>

    public init(_ hosts: [PairedHost] = []) {
        stored = Mutex(Dictionary(hosts.map { ($0.hostID, $0) }, uniquingKeysWith: { $1 }))
    }

    public func hosts() throws -> [PairedHost] {
        stored.withLock { $0.values.sorted { $0.pairedAt < $1.pairedAt } }
    }

    public func save(_ host: PairedHost) throws {
        stored.withLock { $0[host.hostID] = host }
    }

    public func remove(_ hostID: HostID) throws {
        _ = stored.withLock { $0.removeValue(forKey: hostID) }
    }
}
