import ACP
import Foundation
import NativeHostProtocol

// MARK: - Records

struct StoredSession: Hashable {
    var id: HostSessionID
    var agentID: String
    var agentSessionID: SessionID?
    var cwd: String
    var parentID: HostSessionID?
    var origin: SessionOrigin
    var title: String?
    var createdAt: Date
    var lastActivity: Date?
    var lastStopReason: String?
    var isQueuePaused: Bool
    /// ACP `McpServer` objects for the agent, handed over again on every reload.
    var mcpServers: [JSONValue]

    init(
        id: HostSessionID, agentID: String, agentSessionID: SessionID?, cwd: String, parentID: HostSessionID?,
        origin: SessionOrigin,
        title: String? = nil, createdAt: Date = .now, lastActivity: Date? = nil, lastStopReason: String? = nil,
        isQueuePaused: Bool = false,
        mcpServers: [JSONValue] = []
    ) {
        self.id = id
        self.agentID = agentID
        self.agentSessionID = agentSessionID
        self.cwd = cwd
        self.parentID = parentID
        self.origin = origin
        self.title = title
        self.createdAt = createdAt
        self.lastActivity = lastActivity
        self.lastStopReason = lastStopReason
        self.isQueuePaused = isQueuePaused
        self.mcpServers = mcpServers
    }

    init?(row: [SQLiteDatabase.Value]) {
        guard let id = row[0].text.flatMap(UUID.init(uuidString:)), let agentID = row[1].text, let cwd = row[3].text,
            let createdAt = row[7].date
        else { return nil }
        let servers = row[11].text.flatMap { try? JSONDecoder().decode([JSONValue].self, from: Data($0.utf8)) } ?? []
        self.init(
            id: HostSessionID(id), agentID: agentID, agentSessionID: row[2].text.map(SessionID.init), cwd: cwd,
            parentID: row[4].text.flatMap(UUID.init(uuidString:)).map(HostSessionID.init),
            origin: row[5].text.flatMap(SessionOrigin.init(rawValue:)) ?? .unknown, title: row[6].text,
            createdAt: createdAt,
            lastActivity: row[8].date, lastStopReason: row[9].text, isQueuePaused: row[10].bool, mcpServers: servers
        )
    }
}

/// A turn that started and hasn't ended. At most one per session.
struct UnfinishedTurn: Hashable {
    enum Kind: String {
        /// A message the user (or a tool, or the queue) sent.
        case prompt
        /// Native telling the agent its previous turn was interrupted.
        case recovery
    }

    var sessionID: HostSessionID
    var requestID: UUID
    var text: String
    var kind: Kind
    var echo: Bool
    var startedAt: Date
    /// How many times recovery has already tried to finish this turn.
    var attempts: Int

    init(
        sessionID: HostSessionID, requestID: UUID, text: String, kind: Kind, echo: Bool, startedAt: Date = .now,
        attempts: Int = 0
    ) {
        self.sessionID = sessionID
        self.requestID = requestID
        self.text = text
        self.kind = kind
        self.echo = echo
        self.startedAt = startedAt
        self.attempts = attempts
    }

    init?(row: [SQLiteDatabase.Value]) {
        guard let session = row[0].text.flatMap(UUID.init(uuidString:)),
            let request = row[1].text.flatMap(UUID.init(uuidString:)),
            let text = row[2].text, let kind = row[3].text.flatMap(Kind.init(rawValue:)), let startedAt = row[5].date
        else { return nil }
        self.init(
            sessionID: HostSessionID(session), requestID: request, text: text, kind: kind, echo: row[4].bool,
            startedAt: startedAt, attempts: Int(row[6].integer ?? 0))
    }
}

struct StoredQueueItem: Hashable {
    var prompt: QueuedPrompt
    /// Being steered into the running turn right now. If the host stops before the agent answers,
    /// recovery checks the agent's transcript to see whether it arrived.
    var isSteering: Bool
}
