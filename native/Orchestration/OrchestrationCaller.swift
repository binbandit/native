import Foundation

/// The session calling an orchestration tool, named by the token in the URL it was given.
nonisolated struct OrchestrationCaller: Sendable {
    var clientID: UUID
    var agent: AgentDefinition.ID
}
