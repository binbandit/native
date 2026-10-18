import ACP
import Foundation

/// A session a usage limit stopped, described well enough to find it again after a relaunch and
/// to name it in a notification.
struct LimitTarget: Codable, Hashable, Identifiable {
    struct ID: Codable, Hashable {
        let agent: AgentDefinition.ID
        let session: SessionID
    }

    let agent: AgentDefinition.ID
    let agentName: String
    let session: SessionID
    var title: String?

    var id: ID { ID(agent: agent, session: session) }

    init(agent: AgentDefinition.ID, agentName: String, session: SessionID, title: String? = nil) {
        self.agent = agent
        self.agentName = agentName
        self.session = session
        self.title = title
    }

    /// Nil for a session the agent hasn't created yet, or a subagent: neither can be prompted.
    init?(_ context: SessionContext) {
        guard let session = context.sessionID, context.parentID == nil else { return nil }
        self.init(agent: context.agent, agentName: context.agentName, session: session, title: context.title)
    }
}
