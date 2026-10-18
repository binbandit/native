import Foundation

/// The session calling an orchestration tool, named by the token in the URL it was given.
nonisolated struct OrchestrationCaller: Sendable {
    var clientID: UUID
    var agent: AgentDefinition.ID
    /// The session's folder, for what depends on the project (such as which MCP servers its scripts
    /// can reach).
    var cwd: URL
}
