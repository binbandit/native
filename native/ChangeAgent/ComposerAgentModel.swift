import ACP
import Foundation

/// A model retains the identity of the adapter that reported it, even when names or values collide.
struct ComposerAgentModel: Identifiable, Equatable {
    enum Kind: Equatable {
        case model(String?)
        case load
    }

    let agent: AgentDefinition.ID
    let agentName: String
    let choice: ConfigOption.SelectOption
    var kind: Kind
    var unavailable: String?
    var isManaged = false

    var id: String { "\(agent.rawValue.count):\(agent.rawValue)\(choice.value)" }
    var listChoice: ConfigOption.SelectOption {
        .init(value: id, name: choice.name)
    }
    var searchTerms: [String] { [agentName, choice.value] }
    var caption: String {
        if let unavailable { return unavailable }
        switch kind {
        case .load: return "Load \(agentName)'s reported models without sending a message."
        case .model(nil): return "\(agentName) chooses its model. Your draft stays."
        case .model: return "Continues this task with \(agentName). Your draft stays."
        }
    }
}
