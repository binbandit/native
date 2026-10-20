import ACP

/// Requests to an agent outside any one session's turns: listing, deleting and closing its
/// sessions, and signing in. An agent Native runs itself answers on its `ACPConnection`; one running
/// in Native's host answers through the host (`HostAgentConnection`).
nonisolated protocol AgentConnection: Sendable {
    func send<Request: ACPRequest>(_ request: Request) async throws -> Request.Response
}

extension ACPConnection: AgentConnection {}
