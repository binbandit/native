import Foundation

/// Signs in with one of the `authMethods` the agent advertised in `initialize`. The agent runs the
/// flow itself (a browser login, say) and answers once it's done, which can take a while.
public struct AuthenticateRequest: ACPRequest {
    public typealias Response = EmptyResponse
    public static let method = "authenticate"

    public var methodId: String

    public init(methodId: String) {
        self.methodId = methodId
    }
}

extension RPCError {
    /// ACP's `auth_required`: the agent needs the user to sign in (see `AuthenticateRequest`) before
    /// it can serve the request.
    public var isAuthRequired: Bool {
        code == -32000
    }
}
