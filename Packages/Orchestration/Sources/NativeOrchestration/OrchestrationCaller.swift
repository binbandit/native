import Foundation

/// The session calling one of Native's tools, named by the token in the URL it was given.
public struct OrchestrationCaller: Hashable, Sendable {
    /// Native's id for the session (`SessionContext.clientID`, the host's session id), which its
    /// token names.
    public var clientID: UUID
    public var agent: String
    /// The session's folder, for what depends on the project (such as which MCP servers its scripts
    /// can reach).
    public var cwd: URL

    public init(clientID: UUID, agent: String, cwd: URL) {
        self.clientID = clientID
        self.agent = agent
        self.cwd = cwd
    }
}

/// An agent that can run a task.
public struct TaskAgent: Hashable, Sendable {
    public var id: String
    public var name: String

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}
