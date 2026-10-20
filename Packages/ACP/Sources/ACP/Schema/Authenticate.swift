import Foundation

/// Signs in with one of the `authMethods` the agent advertised in `initialize`. The agent runs the
/// flow itself (a browser login, say) and answers once it's done, which can take a while.
public struct AuthenticateRequest: ACPRequest {
    public typealias Response = EmptyResponse
    public static let method = "authenticate"

    public var methodId: String
    /// For an `apiKey` method: the key, sent in `_meta["api-key"].apiKey`. Never printed.
    public var apiKey: String?

    public init(methodId: String, apiKey: String? = nil) {
        self.methodId = methodId
        self.apiKey = apiKey
    }

    private enum CodingKeys: String, CodingKey {
        case methodId, _meta
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(methodId, forKey: .methodId)
        if let apiKey {
            try container.encode(JSONValue.object(["api-key": .object(["apiKey": .string(apiKey)])]), forKey: ._meta)
        }
    }
}

extension AuthenticateRequest: CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    public var description: String {
        "AuthenticateRequest(methodId: \(methodId)\(apiKey == nil ? "" : ", apiKey: <redacted>"))"
    }

    public var debugDescription: String { description }

    public var customMirror: Mirror {
        Mirror(self, children: ["methodId": methodId])
    }
}

/// Signs the agent out of whatever it's signed in with (`AgentAuthCapabilities.logout`).
public struct LogoutRequest: ACPRequest {
    public typealias Response = EmptyResponse
    public static let method = "logout"

    public init() {}
}

extension RPCError {
    /// ACP's `auth_required`: the agent needs the user to sign in (see `AuthenticateRequest`) before
    /// it can serve the request.
    public var isAuthRequired: Bool {
        code == -32000
    }
}
