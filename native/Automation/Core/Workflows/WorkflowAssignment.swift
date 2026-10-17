import Foundation

/// The agent each step of a run gets. Resolved once, when the run starts, from the definition's
/// choices, the user's overrides in the picker and the agents available, so the picker can show the
/// exact plan before anything runs.
nonisolated struct WorkflowAssignment: Codable, Hashable, Sendable {
    /// Nil for pull request steps.
    var agent: WorkflowAgent?
    /// Why the step didn't get what the definition asked for, when it didn't.
    var note: String?

    /// Assigns every step. `overrides` are the user's picks by step id, which beat the definition.
    static func resolve(
        _ definition: WorkflowDefinition,
        agents: [WorkflowAgent],
        defaultAgent: WorkflowAgent.ID?,
        overrides: [String: WorkflowAgent.ID] = [:]
    ) -> [String: WorkflowAssignment] {
        let fallback = agents.first { $0.id == defaultAgent } ?? agents.first
        var assigned: [String: WorkflowAssignment] = [:]
        // Definition order is a valid run order (`WorkflowIssue`), so references resolve first.
        for step in definition.steps {
            guard step.kind == .agent else {
                assigned[step.id] = WorkflowAssignment(agent: nil)
                continue
            }
            if let continued = step.continues {
                assigned[step.id] = WorkflowAssignment(agent: assigned[continued]?.agent)
                continue
            }
            if let override = overrides[step.id], let agent = agents.first(where: { $0.id == override }) {
                assigned[step.id] = WorkflowAssignment(agent: agent)
                continue
            }
            assigned[step.id] = choose(step.agent, assigned: assigned, agents: agents, fallback: fallback)
        }
        return assigned
    }

    private static func choose(
        _ choice: WorkflowAgentChoice?,
        assigned: [String: WorkflowAssignment],
        agents: [WorkflowAgent],
        fallback: WorkflowAgent?
    ) -> WorkflowAssignment {
        switch choice {
        case nil:
            return WorkflowAssignment(agent: fallback)
        case .agent(let id):
            if let agent = agents.first(where: { $0.id == id }) {
                return WorkflowAssignment(agent: agent)
            }
            return WorkflowAssignment(agent: fallback, note: "\(id) isn't available, so this runs on \(fallback?.name ?? "the default agent").")
        case .sameAs(let step):
            return WorkflowAssignment(agent: assigned[step]?.agent ?? fallback)
        case .differentFrom(let step):
            let avoided = assigned[step]?.agent
            if let other = agents.first(where: { $0.id != avoided?.id && $0.id == fallback?.id }) ?? agents.first(where: { $0.id != avoided?.id }) {
                return WorkflowAssignment(agent: other)
            }
            return WorkflowAssignment(agent: avoided ?? fallback, note: "Only one agent is available, so this runs on the same agent as \"\(step)\".")
        }
    }
}
