import ACP
import Foundation

/// A session Usage refers to across launches and notifications: enough to find it again and to
/// name it.
struct UsageSessionRef: Codable, Hashable, Identifiable {
    struct ID: Codable, Hashable {
        let agent: AgentDefinition.ID
        let session: SessionID
    }

    let agent: AgentDefinition.ID
    let agentName: String
    let session: SessionID
    var title: String?
    /// The session that started this one, for an agent's own subagents.
    var parent: SessionID?

    var id: ID { ID(agent: agent, session: session) }

    /// Subagents take work only from their parent, so they can't be resumed.
    var isPromptable: Bool { parent == nil }

    init(
        agent: AgentDefinition.ID, agentName: String, session: SessionID, title: String? = nil, parent: SessionID? = nil
    ) {
        self.agent = agent
        self.agentName = agentName
        self.session = session
        self.title = title
        self.parent = parent
    }

    /// Nil while `session/new` is in flight and the agent's id doesn't exist yet.
    init?(_ context: SessionContext) {
        guard let session = context.sessionID else { return nil }
        self.init(
            agent: context.agent, agentName: context.agentName, session: session, title: context.title,
            parent: context.parentID)
    }
}
