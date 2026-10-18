import Foundation
import NativeAutomation

/// The agents on a crew, by role. Any agent can take any role, and the same agent can take several:
/// the point is to mix providers, not to require them.
public nonisolated struct Crew: Codable, Hashable, Sendable {
    /// Plans the route, revises it between legs, and writes the debrief.
    public var lead: WorkflowAgent
    /// Carry out assignments. Never empty.
    public var builders: [WorkflowAgent]
    /// Checks each leg against its criteria.
    public var reviewer: WorkflowAgent

    public init(lead: WorkflowAgent, builders: [WorkflowAgent], reviewer: WorkflowAgent) {
        self.lead = lead
        self.builders = builders.isEmpty ? [lead] : builders
        self.reviewer = reviewer
    }

    /// Every agent on the crew once, lead first.
    public var agents: [WorkflowAgent] {
        var seen = Set<String>()
        return ([lead] + builders + [reviewer]).filter { seen.insert($0.id).inserted }
    }

    public func agent(_ id: String) -> WorkflowAgent? {
        agents.first { $0.id == id }
    }

    /// The suggested crew from the agents that are available: the preferred agent leads, it and
    /// one other provider build, and that other provider reviews, since a second provider catches
    /// what the first one's habits miss. Small on purpose; the user adds more.
    public static func suggested(from agents: [WorkflowAgent], preferring preferred: WorkflowAgent.ID?) -> Crew? {
        guard let lead = agents.first(where: { $0.id == preferred }) ?? agents.first else { return nil }
        let other = agents.first { $0.id != lead.id }
        return Crew(lead: lead, builders: [lead] + [other].compactMap(\.self), reviewer: other ?? lead)
    }

    /// Whether the reviewer is the only provider building too, so it checks its own habits.
    public var reviewerIsOnlyBuilder: Bool {
        builders.allSatisfy { $0.id == reviewer.id }
    }
}

/// A seat on the crew that runs turns: the lead, an assignment, or a leg's checkpoint.
public nonisolated enum CrewSlot: Codable, Hashable, Sendable {
    case lead
    case assignment(String)
    case checkpoint(String)
}
