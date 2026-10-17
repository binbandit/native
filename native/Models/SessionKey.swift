import ACP

/// Identifies a session across agents, whose session ids can collide.
struct SessionKey: Hashable, Codable, Sendable {
    let agent: AgentDefinition.ID
    let id: SessionID
}
