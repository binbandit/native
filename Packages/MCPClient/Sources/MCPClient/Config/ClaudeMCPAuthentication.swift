import CryptoKit
import Foundation

/// Reads Claude Code's shared OAuth record without copying its token to a probe, refreshing it or
/// changing it. Keychain takes precedence over the plaintext fallback, as in Claude Code 2.1.306.
public struct ClaudeMCPAuthentication: Sendable {
    private let files: any ConfigFileSystem
    private let keychain: any MCPCredentialKeychain

    public init(files: any ConfigFileSystem, keychain: any MCPCredentialKeychain = LocalMCPCredentialKeychain()) {
        self.files = files
        self.keychain = keychain
    }

    public func read(
        _ configuration: AgentMCPConfiguration, home: URL, environment: [String: String], now: Date = .now
    ) -> AgentMCPConfiguration {
        guard configuration.format == .claudeCode,
            configuration.servers.contains(where: { $0.server.transport.url != nil })
        else { return configuration }
        var result = configuration
        let credentials = credentials(home: home, environment: environment)
        for index in result.servers.indices {
            let entry = result.servers[index]
            let server = entry.resolved(environment: environment, project: entry.scope.project)
            result.servers[index].authentication = status(of: server, in: credentials, now: now)
        }
        return result
    }

    private func credentials(home: URL, environment: [String: String]) -> [String: Credential]? {
        let override = environment["CLAUDE_SECURESTORAGE_CONFIG_DIR"] ?? environment["CLAUDE_CONFIG_DIR"]
        let directory =
            override.flatMap { $0.isEmpty ? nil : $0 }?.precomposedStringWithCanonicalMapping
            ?? home.appending(path: ".claude").path(percentEncoded: false)
        let suffix = override.map { $0.isEmpty ? "" : "-" + Self.digest(directory, count: 8) } ?? ""
        let account = environment["USER"] ?? NSUserName()
        let safeAccount =
            account.range(of: "^[a-zA-Z0-9._-]+$", options: .regularExpression) == nil
            ? "claude-code-user" : account
        do {
            let keychainData = try keychain.data(service: "Claude Code-credentials" + suffix, account: safeAccount)
            let path = URL(filePath: directory).appending(path: ".credentials.json").path(percentEncoded: false)
            guard let data = keychainData ?? files.contents(atPath: path) else {
                return files.fileExists(atPath: path) ? nil : [:]
            }
            return try JSONDecoder().decode(Store.self, from: data).mcpOAuth ?? [:]
        } catch {
            // A locked, denied or corrupt store isn't evidence that the user signed out. Don't
            // fall back to a potentially stale file when the authoritative store is unreadable.
            return nil
        }
    }

    private func status(
        of server: MCPServerConfig, in credentials: [String: Credential]?, now: Date
    )
        -> MCPAuthenticationStatus
    {
        guard let credentials else { return .unknown }
        let type: String
        let url: URL
        let headers: [String: String]
        switch server.transport {
        case .stdio: return .unknown
        case .http(let address, let values): (type, url, headers) = ("http", address, values)
        case .sse(let address, let values): (type, url, headers) = ("sse", address, values)
        }
        // Claude hashes JSON.stringify's header order. Configuration decoding doesn't preserve
        // that order, so multiple headers cannot safely identify a credential record here.
        guard headers.count <= 1,
            !headers.keys.contains(where: { $0.caseInsensitiveCompare("Authorization") == .orderedSame }),
            let typeJSON = Self.json(type), let urlJSON = Self.json(url.absoluteString),
            let headersJSON = Self.json(headers)
        else { return .unknown }
        let payload = "{\"type\":\(typeJSON),\"url\":\(urlJSON),\"headers\":\(headersJSON)}"
        let key = server.name + "|" + Self.digest(payload, count: 16)
        guard let credential = credentials[key] else { return .signedOut }
        guard credential.serverName == server.name, credential.serverUrl == url.absoluteString else { return .unknown }
        let hasRefresh = credential.refreshToken?.isEmpty == false
        let hasAccess = credential.accessToken?.isEmpty == false
        let unexpired = credential.expiresAt.map { $0 > now.timeIntervalSince1970 * 1_000 } ?? true
        return hasRefresh || (hasAccess && unexpired) ? .signedIn : .signedOut
    }

    private static func digest(_ text: String, count: Int) -> String {
        String(SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined().prefix(count))
    }

    private static func json(_ value: Any) -> String? {
        guard
            let data = try? JSONSerialization.data(
                withJSONObject: value, options: [.fragmentsAllowed, .withoutEscapingSlashes])
        else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private struct Store: Decodable {
        var mcpOAuth: [String: Credential]?
    }

    private struct Credential: Decodable {
        var serverName: String
        var serverUrl: String
        var accessToken: String?
        var refreshToken: String?
        var expiresAt: Double?
    }
}
