import Foundation

/// What `gh auth status --json hosts` reports: the accounts gh holds, by host.
public struct AuthStatus: Sendable, Hashable, Decodable {
    public var hosts: [String: [Account]]

    public init(hosts: [String: [Account]]) {
        self.hosts = hosts
    }

    /// The account gh uses for each host, sorted by host.
    public var activeAccounts: [Account] {
        hosts.keys.sorted().compactMap { host in hosts[host]?.first(where: \.active) }
    }

    /// One login gh holds for a host.
    public struct Account: Sendable, Hashable, Decodable {
        public enum State: String, Sendable, Hashable, GitHubEnum {
            /// The token works.
            case success = "SUCCESS"
            /// The token was rejected: expired, revoked or missing scopes.
            case error = "ERROR"
            /// The host didn't answer while gh checked the token.
            case timeout = "TIMEOUT"
            case other
        }

        public var host: String
        public var login: String
        /// gh keeps one active account per host and uses it for every command.
        public var active: Bool
        public var state: State?
        /// "keyring", "oauth_token" (gh's config file), "GH_TOKEN", ...
        public var tokenSource: String?
        /// Comma-separated OAuth scopes.
        public var scopes: String?

        public init(
            host: String, login: String, active: Bool, state: State?, tokenSource: String? = nil, scopes: String? = nil
        ) {
            self.host = host
            self.login = login
            self.active = active
            self.state = state
            self.tokenSource = tokenSource
            self.scopes = scopes
        }

        private enum CodingKeys: String, CodingKey {
            case host, login, active, state, tokenSource, scopes
        }

        public init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            host = try container.decode(String.self, forKey: .host)
            login = try container.decode(String.self, forKey: .login)
            active = try container.decodeIfPresent(Bool.self, forKey: .active) ?? false
            state = try container.decodeEnum(State.self, forKey: .state)
            tokenSource = try container.decodeText(forKey: .tokenSource)
            scopes = try container.decodeText(forKey: .scopes)
        }
    }
}
