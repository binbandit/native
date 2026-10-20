import Foundation

/// Who an agent says it's signed in as. Claude Code's and Codex's adapters push it in an
/// `_auth/status_update` notification right after `initialize` and whenever it changes
/// (`AgentAuthCapabilities.reportsStatus`): an extension until ACP has its own. "Can't tell" is no
/// notification at all, never a status.
public struct AgentAuthStatus: Codable, Hashable, Sendable {
    public enum Kind: Hashable, Sendable {
        /// Known to be signed out (`"none"` on the wire).
        case signedOut
        /// A subscription login ("ChatGPT Pro", "Claude Max").
        case account
        case apiKey
        /// A custom model gateway.
        case gateway
        /// Credentials kept outside the agent (a cloud provider's).
        case external
        case unknown(String)

        init(wire: String) {
            self =
                switch wire {
                case "none": .signedOut
                case "account": .account
                case "api_key": .apiKey
                case "gateway": .gateway
                case "external": .external
                default: .unknown(wire)
                }
        }

        var wire: String {
            switch self {
            case .signedOut: "none"
            case .account: "account"
            case .apiKey: "api_key"
            case .gateway: "gateway"
            case .external: "external"
            case .unknown(let wire): wire
            }
        }
    }

    public var kind: Kind
    /// What the agent calls it: "ChatGPT Pro", "Anthropic API key", "Not logged in".
    public var label: String
    /// More about it, such as where a key comes from or a gateway's host.
    public var detail: String?
    public var email: String?

    public init(kind: Kind, label: String, detail: String? = nil, email: String? = nil) {
        self.kind = kind
        self.label = label
        self.detail = detail
        self.email = email
    }

    /// Anything but known to be signed out.
    public var isSignedIn: Bool {
        kind != .signedOut
    }

    private enum CodingKeys: String, CodingKey {
        case kind, label, detail, account
    }

    private struct Account: Codable, Hashable {
        var email: String?
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        kind = Kind(wire: try container.decode(String.self, forKey: .kind))
        label = try container.decodeIfPresent(String.self, forKey: .label) ?? ""
        detail = try container.decodeIfPresent(String.self, forKey: .detail)
        email = try container.decodeIfPresent(Account.self, forKey: .account)?.email
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(kind.wire, forKey: .kind)
        try container.encode(label, forKey: .label)
        try container.encodeIfPresent(detail, forKey: .detail)
        try container.encodeIfPresent(email.map { Account(email: $0) }, forKey: .account)
    }
}

/// The `_auth/status_update` notification's params.
public struct AuthStatusNotification: Decodable, Sendable {
    public static let method = "_auth/status_update"

    public var authStatus: AgentAuthStatus
}

/// What an agent supports around signing in, read from its `initialize` result.
public struct AgentAuthCapabilities: Hashable, Sendable {
    /// `agentCapabilities.auth.logout`: it signs out on a `LogoutRequest`.
    public var logout: Bool
    /// `agentCapabilities._meta.authStatus`: it sends `AuthStatusNotification`s.
    public var reportsStatus: Bool

    public init(logout: Bool = false, reportsStatus: Bool = false) {
        self.logout = logout
        self.reportsStatus = reportsStatus
    }

    public init(initializeResult: JSONValue?) {
        let capabilities = initializeResult?["agentCapabilities"]
        logout = capabilities?["auth"]?["logout"].map { $0 != .null } ?? false
        reportsStatus = capabilities?["_meta"]?["authStatus"].map { $0 != .null } ?? false
    }
}
