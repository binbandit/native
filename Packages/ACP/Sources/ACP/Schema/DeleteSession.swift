import Foundation

/// Deletes a session from the agent's own store. Only for agents that advertise
/// `sessionCapabilities.delete`.
public struct DeleteSessionRequest: ACPRequest {
    public typealias Response = EmptyResponse
    public static let method = "session/delete"

    public var sessionId: SessionID

    public init(sessionId: SessionID) {
        self.sessionId = sessionId
    }
}
