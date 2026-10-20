import Foundation
import NativeHost
import NativeHostProtocol
import Security

/// Agents' keys in the user's login keychain, one generic password each (service `service`,
/// account `<agent>/<method>`), never synced to iCloud. Only this host's binary can read them
/// without the user being asked: a development build, re-signed on every build, would be asked
/// each time, and a host nobody sits at can't answer, so those use `HostCredentialFile`
/// (`MacHost.configuration`).
public struct HostKeychain: HostCredentialStore {
    public let service: String

    public init(service: String) {
        self.service = service
    }

    public func load() throws -> [HostCredential] {
        var result: CFTypeRef?
        let status = SecItemCopyMatching(
            query([kSecMatchLimit: kSecMatchLimitAll, kSecReturnAttributes: true]) as CFDictionary, &result)
        if status == errSecItemNotFound { return [] }
        try Self.check(status, "read")
        let accounts = (result as? [[String: Any]] ?? []).compactMap { $0[kSecAttrAccount as String] as? String }
        return try accounts.compactMap(credential(account:))
    }

    public func save(_ credential: HostCredential) throws {
        let data = try JSONEncoder().encode(credential)
        let account = Self.account(agentID: credential.agentID, methodID: credential.methodID)
        let status = SecItemUpdate(
            query([kSecAttrAccount: account]) as CFDictionary, [kSecValueData: data] as CFDictionary)
        if status == errSecItemNotFound {
            try Self.check(
                SecItemAdd(
                    query([
                        kSecAttrAccount: account, kSecValueData: data, kSecAttrLabel: "\(service): \(account)",
                    ]) as CFDictionary, nil), "save")
        } else {
            try Self.check(status, "save")
        }
    }

    public func remove(agentID: String, methodID: String) throws {
        let status = SecItemDelete(
            query([kSecAttrAccount: Self.account(agentID: agentID, methodID: methodID)]) as CFDictionary)
        guard status != errSecItemNotFound else { return }
        try Self.check(status, "remove")
    }

    private func credential(account: String) throws -> HostCredential? {
        var result: CFTypeRef?
        let status = SecItemCopyMatching(
            query([kSecAttrAccount: account, kSecMatchLimit: kSecMatchLimitOne, kSecReturnData: true])
                as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        try Self.check(status, "read")
        guard let data = result as? Data else { return nil }
        return try JSONDecoder().decode(HostCredential.self, from: data)
    }

    private func query(_ extra: [CFString: Any]) -> [CFString: Any] {
        [kSecClass: kSecClassGenericPassword, kSecAttrService: service, kSecAttrSynchronizable: false]
            .merging(extra) { $1 }
    }

    private static func account(agentID: String, methodID: String) -> String {
        "\(agentID)/\(methodID)"
    }

    private static func check(_ status: OSStatus, _ operation: String) throws {
        guard status != errSecSuccess else { return }
        throw Failure(operation: operation, status: status)
    }

    struct Failure: Error, LocalizedError {
        var operation: String
        var status: OSStatus

        var errorDescription: String? {
            let reason = SecCopyErrorMessageString(status, nil) as String? ?? "error \(status)"
            return "Couldn't \(operation) the host's saved keys in the keychain: \(reason)."
        }
    }
}

extension MacHost {
    /// The keychain for a release host at its standard location. Development builds (asked on every
    /// rebuild) and hosts in a folder of their own (tests, `native-host serve --home`) keep keys in
    /// that folder's `credentials.json` instead (nil here).
    static func credentialStore(for location: HostLocation) -> (any HostCredentialStore)? {
        guard !location.isDevelopment, location == .standard(channel: location.channel) else { return nil }
        return HostKeychain(service: location.channel.isEmpty ? "Native Host" : "Native Host (\(location.channel))")
    }
}
