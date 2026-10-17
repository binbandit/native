import ACP
import Foundation
import NativeHostProtocol

/// Native's own durable state, in one SQLite database owned by the host. Conversations aren't here:
/// they live in each agent's store and come back with `session/load`. What is here is everything
/// only Native knows: which sessions are open, the turn in flight, queued messages, prompt request
/// ids, approvals waiting on the user, and the activity journal.
///
/// Every change is committed with `synchronous=FULL` and `fullfsync`, so once a method returns, the
/// change survives the host being killed and the Mac losing power. Writes happen per user action
/// and turn boundary, never per streamed token, so the cost of a full sync doesn't show.
final class HostStore {
    private let database: SQLiteDatabase

    private static let schemaVersion: Int64 = 1

    init(url: URL) throws {
        database = try SQLiteDatabase(url: url)
        try database.execute("""
            PRAGMA journal_mode = WAL;
            PRAGMA synchronous = FULL;
            PRAGMA fullfsync = ON;
            PRAGMA checkpoint_fullfsync = ON;
            PRAGMA foreign_keys = ON;
            """)
        try migrate()
    }

    /// Runs `body` as one transaction, for changes that must land together (a turn and the request
    /// id that started it).
    func transaction<Result>(_ body: () throws -> Result) throws -> Result {
        try database.transaction(body)
    }

    private func migrate() throws {
        let version = try database.query("PRAGMA user_version").first?.first?.integer ?? 0
        guard version < Self.schemaVersion else { return }
        try database.transaction {
            try database.execute("""
                CREATE TABLE IF NOT EXISTS meta (key TEXT PRIMARY KEY, value TEXT NOT NULL);
                CREATE TABLE IF NOT EXISTS agents (id TEXT PRIMARY KEY, spec TEXT NOT NULL);
                CREATE TABLE IF NOT EXISTS sessions (
                    id TEXT PRIMARY KEY,
                    agent_id TEXT NOT NULL,
                    agent_session_id TEXT,
                    cwd TEXT NOT NULL,
                    parent_id TEXT REFERENCES sessions(id) ON DELETE SET NULL,
                    origin TEXT NOT NULL,
                    title TEXT,
                    created_at REAL NOT NULL,
                    last_activity REAL,
                    last_stop_reason TEXT,
                    queue_paused INTEGER NOT NULL DEFAULT 0,
                    mcp_servers TEXT NOT NULL DEFAULT '[]'
                );
                CREATE UNIQUE INDEX IF NOT EXISTS sessions_agent_session ON sessions(agent_id, agent_session_id);
                CREATE TABLE IF NOT EXISTS turns (
                    session_id TEXT PRIMARY KEY REFERENCES sessions(id) ON DELETE CASCADE,
                    request_id TEXT NOT NULL,
                    text TEXT NOT NULL,
                    kind TEXT NOT NULL,
                    echo INTEGER NOT NULL,
                    started_at REAL NOT NULL,
                    attempts INTEGER NOT NULL DEFAULT 0
                );
                CREATE TABLE IF NOT EXISTS queue (
                    session_id TEXT NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,
                    position INTEGER NOT NULL,
                    id TEXT NOT NULL,
                    text TEXT NOT NULL,
                    echo INTEGER NOT NULL,
                    steering INTEGER NOT NULL DEFAULT 0,
                    PRIMARY KEY (session_id, position)
                );
                CREATE TABLE IF NOT EXISTS requests (
                    request_id TEXT PRIMARY KEY,
                    session_id TEXT NOT NULL,
                    delivery TEXT NOT NULL,
                    at REAL NOT NULL
                );
                CREATE TABLE IF NOT EXISTS approvals (
                    session_id TEXT NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,
                    tool_call_id TEXT NOT NULL,
                    title TEXT,
                    requested_at REAL NOT NULL,
                    PRIMARY KEY (session_id, tool_call_id)
                );
                CREATE TABLE IF NOT EXISTS activity (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    at REAL NOT NULL,
                    session_id TEXT,
                    kind TEXT NOT NULL,
                    subject TEXT,
                    detail TEXT,
                    recovery TEXT
                );
                """)
            try database.execute("PRAGMA user_version = \(Self.schemaVersion)")
        }
    }

    // MARK: - Meta

    func meta(_ key: String) throws -> String? {
        try database.query("SELECT value FROM meta WHERE key = ?", .text(key)).first?.first?.text
    }

    func setMeta(_ key: String, _ value: String?) throws {
        if let value {
            try database.run("INSERT INTO meta (key, value) VALUES (?, ?) ON CONFLICT(key) DO UPDATE SET value = excluded.value", .text(key), .text(value))
        } else {
            try database.run("DELETE FROM meta WHERE key = ?", .text(key))
        }
    }

    // MARK: - Agents

    func replaceAgents(_ agents: [AgentSpec]) throws {
        let encoder = JSONEncoder()
        try database.transaction {
            try database.run("DELETE FROM agents")
            for agent in agents {
                try database.run("INSERT INTO agents (id, spec) VALUES (?, ?)", .text(agent.id), .text(String(decoding: try encoder.encode(agent), as: UTF8.self)))
            }
        }
    }

    func agents() throws -> [AgentSpec] {
        let decoder = JSONDecoder()
        return try database.query("SELECT spec FROM agents ORDER BY rowid").compactMap { row in
            try row.first?.text.map { try decoder.decode(AgentSpec.self, from: Data($0.utf8)) }
        }
    }

    // MARK: - Sessions

    func insertSession(_ session: StoredSession) throws {
        try database.run(
            """
            INSERT INTO sessions (id, agent_id, agent_session_id, cwd, parent_id, origin, title, created_at, last_activity, last_stop_reason, queue_paused, mcp_servers)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            .text(session.id.description), .text(session.agentID), .text(session.agentSessionID?.rawValue), .text(session.cwd),
            .text(session.parentID?.description), .text(session.origin.rawValue), .text(session.title), .date(session.createdAt),
            .date(session.lastActivity), .text(session.lastStopReason), .bool(session.isQueuePaused),
            .text(String(decoding: try JSONEncoder().encode(session.mcpServers), as: UTF8.self))
        )
    }

    func updateSession(_ session: StoredSession) throws {
        try database.run(
            """
            UPDATE sessions SET agent_session_id = ?, title = ?, last_activity = ?, last_stop_reason = ?, queue_paused = ?
            WHERE id = ?
            """,
            .text(session.agentSessionID?.rawValue), .text(session.title), .date(session.lastActivity), .text(session.lastStopReason),
            .bool(session.isQueuePaused), .text(session.id.description)
        )
    }

    func deleteSession(_ id: HostSessionID) throws {
        try database.run("DELETE FROM sessions WHERE id = ?", .text(id.description))
    }

    func sessions() throws -> [StoredSession] {
        try database.query(
            """
            SELECT id, agent_id, agent_session_id, cwd, parent_id, origin, title, created_at, last_activity, last_stop_reason, queue_paused, mcp_servers
            FROM sessions ORDER BY created_at
            """
        ).compactMap(StoredSession.init(row:))
    }

    // MARK: - Turns

    /// Records the turn about to start. Called before its prompt is written to the agent, so a turn
    /// cut off at any point afterwards is found again.
    func beginTurn(_ turn: UnfinishedTurn) throws {
        try database.run(
            """
            INSERT INTO turns (session_id, request_id, text, kind, echo, started_at, attempts) VALUES (?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(session_id) DO UPDATE SET request_id = excluded.request_id, text = excluded.text, kind = excluded.kind,
                echo = excluded.echo, started_at = excluded.started_at, attempts = excluded.attempts
            """,
            .text(turn.sessionID.description), .text(turn.requestID.uuidString), .text(turn.text), .text(turn.kind.rawValue),
            .bool(turn.echo), .date(turn.startedAt), .integer(Int64(turn.attempts))
        )
    }

    func finishTurn(_ sessionID: HostSessionID) throws {
        try database.run("DELETE FROM turns WHERE session_id = ?", .text(sessionID.description))
    }

    func unfinishedTurns() throws -> [UnfinishedTurn] {
        try database.query("SELECT session_id, request_id, text, kind, echo, started_at, attempts FROM turns").compactMap(UnfinishedTurn.init(row:))
    }

    // MARK: - Queue

    /// Replaces a session's queue. Queues are a handful of messages, so writing the whole thing keeps
    /// the order trivially right.
    func setQueue(_ items: [StoredQueueItem], for sessionID: HostSessionID) throws {
        try database.run("DELETE FROM queue WHERE session_id = ?", .text(sessionID.description))
        for (position, item) in items.enumerated() {
            try database.run(
                "INSERT INTO queue (session_id, position, id, text, echo, steering) VALUES (?, ?, ?, ?, ?, ?)",
                .text(sessionID.description), .integer(Int64(position)), .text(item.prompt.id.uuidString), .text(item.prompt.text),
                .bool(item.prompt.isEchoed), .bool(item.isSteering)
            )
        }
    }

    func queue(for sessionID: HostSessionID) throws -> [StoredQueueItem] {
        try database.query("SELECT id, text, echo, steering FROM queue WHERE session_id = ? ORDER BY position", .text(sessionID.description)).compactMap { row in
            guard let id = row[0].text.flatMap(UUID.init(uuidString:)), let text = row[1].text else { return nil }
            return StoredQueueItem(prompt: QueuedPrompt(id: id, text: text, isEchoed: row[2].bool), isSteering: row[3].bool)
        }
    }

    // MARK: - Prompt requests

    /// What a prompt request id was delivered as, if it's been seen before.
    func delivery(for requestID: UUID) throws -> PromptDelivery? {
        try database.query("SELECT delivery FROM requests WHERE request_id = ?", .text(requestID.uuidString)).first?.first?.text.map { PromptDelivery(rawValue: $0) ?? .unknown }
    }

    func recordDelivery(_ delivery: PromptDelivery, for requestID: UUID, in sessionID: HostSessionID) throws {
        try database.run(
            """
            INSERT INTO requests (request_id, session_id, delivery, at) VALUES (?, ?, ?, ?)
            ON CONFLICT(request_id) DO UPDATE SET delivery = excluded.delivery
            """,
            .text(requestID.uuidString), .text(sessionID.description), .text(delivery.rawValue), .date(.now)
        )
    }

    /// Forgets request ids old enough that no client could still be retrying them.
    func pruneRequests(olderThan date: Date) throws {
        try database.run("DELETE FROM requests WHERE at < ?", .date(date))
    }

    // MARK: - Approvals

    func addApproval(sessionID: HostSessionID, toolCallID: String, title: String?) throws {
        try database.run(
            "INSERT OR REPLACE INTO approvals (session_id, tool_call_id, title, requested_at) VALUES (?, ?, ?, ?)",
            .text(sessionID.description), .text(toolCallID), .text(title), .date(.now)
        )
    }

    func removeApproval(sessionID: HostSessionID, toolCallID: String) throws {
        try database.run("DELETE FROM approvals WHERE session_id = ? AND tool_call_id = ?", .text(sessionID.description), .text(toolCallID))
    }

    func removeApprovals(sessionID: HostSessionID) throws {
        try database.run("DELETE FROM approvals WHERE session_id = ?", .text(sessionID.description))
    }

    /// Approvals that were waiting when the host last stopped, by session. Their requests died with
    /// the agent; the agent asks again once the session resumes.
    func approvals() throws -> [HostSessionID: [String]] {
        var approvals: [HostSessionID: [String]] = [:]
        for row in try database.query("SELECT session_id, tool_call_id FROM approvals") {
            guard let session = row[0].text.flatMap(UUID.init(uuidString:)).map(HostSessionID.init), let toolCall = row[1].text else { continue }
            approvals[session, default: []].append(toolCall)
        }
        return approvals
    }

    // MARK: - Activity

    @discardableResult
    func appendActivity(_ kind: ActivityEntry.Kind, session: HostSessionID?, subject: String?, detail: String? = nil, recovery: RecoveryNote? = nil, at: Date = .now) throws -> ActivityEntry {
        let encoded = try recovery.map { String(decoding: try JSONEncoder().encode($0), as: UTF8.self) }
        try database.run(
            "INSERT INTO activity (at, session_id, kind, subject, detail, recovery) VALUES (?, ?, ?, ?, ?, ?)",
            .date(at), .text(session?.description), .text(kind.rawValue), .text(subject), .text(detail), .text(encoded)
        )
        return ActivityEntry(id: database.lastInsertRowID, at: at, sessionID: session, kind: kind, subject: subject, detail: detail, recovery: recovery)
    }

    func activity(after id: Int64?, limit: Int) throws -> [ActivityEntry] {
        let decoder = JSONDecoder()
        return try database.query(
            "SELECT id, at, session_id, kind, subject, detail, recovery FROM activity WHERE id > ? ORDER BY id LIMIT ?",
            .integer(id ?? 0), .integer(Int64(limit))
        ).compactMap { row in
            guard let id = row[0].integer, let at = row[1].date, let kind = row[3].text else { return nil }
            return ActivityEntry(
                id: id, at: at, sessionID: row[2].text.flatMap(UUID.init(uuidString:)).map(HostSessionID.init),
                kind: ActivityEntry.Kind(rawValue: kind) ?? .unknown, subject: row[4].text, detail: row[5].text,
                recovery: row[6].text.flatMap { try? decoder.decode(RecoveryNote.self, from: Data($0.utf8)) }
            )
        }
    }

    // MARK: - Inspection, for tests

    func pragma(_ name: String) throws -> String? {
        let value = try database.query("PRAGMA \(name)").first?.first
        return value?.text ?? value?.integer.map(String.init)
    }
}

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
        id: HostSessionID, agentID: String, agentSessionID: SessionID?, cwd: String, parentID: HostSessionID?, origin: SessionOrigin,
        title: String? = nil, createdAt: Date = .now, lastActivity: Date? = nil, lastStopReason: String? = nil, isQueuePaused: Bool = false,
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

    fileprivate init?(row: [SQLiteDatabase.Value]) {
        guard let id = row[0].text.flatMap(UUID.init(uuidString:)), let agentID = row[1].text, let cwd = row[3].text,
              let createdAt = row[7].date else { return nil }
        let servers = row[11].text.flatMap { try? JSONDecoder().decode([JSONValue].self, from: Data($0.utf8)) } ?? []
        self.init(
            id: HostSessionID(id), agentID: agentID, agentSessionID: row[2].text.map(SessionID.init), cwd: cwd,
            parentID: row[4].text.flatMap(UUID.init(uuidString:)).map(HostSessionID.init),
            origin: row[5].text.flatMap(SessionOrigin.init(rawValue:)) ?? .unknown, title: row[6].text, createdAt: createdAt,
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

    init(sessionID: HostSessionID, requestID: UUID, text: String, kind: Kind, echo: Bool, startedAt: Date = .now, attempts: Int = 0) {
        self.sessionID = sessionID
        self.requestID = requestID
        self.text = text
        self.kind = kind
        self.echo = echo
        self.startedAt = startedAt
        self.attempts = attempts
    }

    fileprivate init?(row: [SQLiteDatabase.Value]) {
        guard let session = row[0].text.flatMap(UUID.init(uuidString:)), let request = row[1].text.flatMap(UUID.init(uuidString:)),
              let text = row[2].text, let kind = row[3].text.flatMap(Kind.init(rawValue:)), let startedAt = row[5].date else { return nil }
        self.init(sessionID: HostSessionID(session), requestID: request, text: text, kind: kind, echo: row[4].bool, startedAt: startedAt, attempts: Int(row[6].integer ?? 0))
    }
}

struct StoredQueueItem: Hashable {
    var prompt: QueuedPrompt
    /// Being steered into the running turn right now. If the host stops before the agent answers,
    /// recovery checks the agent's transcript to see whether it arrived.
    var isSteering: Bool
}
