import Foundation
import LocalAuthentication
import Security

/// Read-only access to agents' shared credential stores. Implemented by the host owning the agent.
public protocol MCPCredentialKeychain: Sendable {
    func data(service: String, account: String) throws -> Data?
}

public struct LocalMCPCredentialKeychain: MCPCredentialKeychain {
    public init() {}

    public func data(service: String, account: String) throws -> Data? {
        #if os(macOS)
        let context = LAContext()
        context.interactionNotAllowed = true
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
            // A status check must never interrupt the user with a Keychain permission dialog.
            kSecUseAuthenticationContext as String: context,
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else {
            throw SecretStoreError(status: status)
        }
        return data
        #else
        // Agents' Mac credentials aren't in an iPad client's Keychain.
        throw SecretStoreError(status: errSecNotAvailable)
        #endif
    }
}
