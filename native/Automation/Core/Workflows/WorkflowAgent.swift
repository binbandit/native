import Foundation

/// An agent a workflow step can run on, as the engine sees it: just enough to assign steps and name
/// them, so the engine doesn't depend on the plugin registry.
nonisolated struct WorkflowAgent: Codable, Hashable, Sendable, Identifiable {
    /// The agent's plugin id (`AgentDefinition.ID.rawValue`).
    var id: String
    var name: String
    /// An SF Symbol.
    var symbol: String

    init(id: String, name: String, symbol: String = "sparkle") {
        self.id = id
        self.name = name
        self.symbol = symbol
    }
}
