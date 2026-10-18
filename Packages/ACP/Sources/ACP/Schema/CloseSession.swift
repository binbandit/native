import Foundation

/// Ends a session in the agent's process, which frees what the agent holds for it (its thread, its
/// MCP servers) without touching its stored history: `session/load` brings it back. Only for agents
/// that advertise `sessionCapabilities.close`.
public struct CloseSessionRequest: ACPRequest {
    public typealias Response = EmptyResponse
    public static let method = "session/close"

    public var sessionId: SessionID

    public init(sessionId: SessionID) {
        self.sessionId = sessionId
    }
}
