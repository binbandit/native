import Foundation
import NativeCommands

/// What ↑, ↓ and Return act on in the agent picker.
enum AgentPickerItem: Hashable {
    case agent(AgentDefinition.ID)
    case addAgent
}

/// What the agent picker lists for what's typed: the matching agents, best first (in their usual
/// order while nothing is typed), matched the way the command palette matches, and the agents Native
/// can't find that Add Agent's row names.
struct AgentPickerResults {
    struct Match {
        let option: AgentPickerOption
        /// The name's matched characters, as character offsets.
        let highlights: [Range<Int>]
    }

    let agents: [Match]
    /// What Add Agent's row names: the missing agents that match what's typed, or all of them while
    /// nothing is typed or nothing else matches. Nil hides the row.
    let missingAgents: [String]?

    init(options: [AgentPickerOption], missingAgents missing: [String], query: String) {
        let query = query.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else {
            agents = options.map { Match(option: $0, highlights: []) }
            missingAgents = missing.isEmpty ? nil : missing
            return
        }
        agents = options.enumerated()
            .compactMap { offset, option in
                FuzzyMatch(query, title: option.name, keywords: [option.id.rawValue]).map {
                    (match: Match(option: option, highlights: $0.highlights), score: $0.score, offset: offset)
                }
            }
            .sorted { ($0.score, -$0.offset) > ($1.score, -$1.offset) }
            .map(\.match)
        let matching = missing.filter { FuzzyMatch(query, title: $0) != nil }
        missingAgents = !matching.isEmpty ? matching : agents.isEmpty && !missing.isEmpty ? missing : nil
    }

    /// The rows ↑ and ↓ move through, in order: the agents that can start a session, then Add Agent.
    var items: [AgentPickerItem] {
        agents.filter { $0.option.choice != nil }.map { .agent($0.option.id) }
            + (missingAgents == nil ? [] : [.addAgent])
    }
}
