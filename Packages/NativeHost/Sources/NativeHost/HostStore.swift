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
    /// Extensions that keep an engine's tables use it directly (HostStore+Notifications.swift).
    let database: SQLiteDatabase

    static let schemaVersion: Int64 = 12

    init(url: URL) throws {
        database = try SQLiteDatabase(url: url)
        try database.execute(
            """
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
            if version < 2 {
                try createVersion2()
            }
            if version < 3 {
                // Version 3: what a prompt carries beyond its text (attachments, content, a preamble),
                // sessions' `_meta` and chosen config values, and activity tied to agent sessions.
                try database.execute(
                    """
                    ALTER TABLE turns ADD COLUMN extra TEXT;
                    ALTER TABLE queue ADD COLUMN extra TEXT;
                    ALTER TABLE sessions ADD COLUMN meta TEXT;
                    ALTER TABLE sessions ADD COLUMN config_choices TEXT NOT NULL DEFAULT '{}';
                    ALTER TABLE activity ADD COLUMN agent_id TEXT;
                    ALTER TABLE activity ADD COLUMN agent_session_id TEXT;
                    ALTER TABLE activity ADD COLUMN previous_run TEXT;
                    """)
            }
            if version < 4 {
                // Version 4: whether a session was adopted from the agent's own list (so the agent
                // saved it) rather than started here.
                try database.execute("ALTER TABLE sessions ADD COLUMN adopted INTEGER NOT NULL DEFAULT 0")
            }
            if version < 5 {
                // Version 5: the folders clients may run commands and read files in.
                try database.execute(
                    "CREATE TABLE IF NOT EXISTS projects (path TEXT PRIMARY KEY, added_at REAL NOT NULL)")
            }
            if version < 6 {
                // Version 6: the notification backlog (HostStore+Notifications.swift).
                try database.execute(Self.notificationsTable)
            }
            if version < 7 {
                // Version 7: each session's titles (HostStore+Titles.swift).
                try database.execute(Self.titlesTable)
            }
            if version < 8 {
                // Version 8: the tasks sessions handed each other (HostStore+Tasks.swift).
                try database.execute(Self.tasksTable)
            }
            if version < 9 {
                try database.execute(Self.closedSessionConfigTable)
            }
            if version < 10 {
                try database.execute(
                    """
                    ALTER TABLE titles ADD COLUMN retry_count INTEGER NOT NULL DEFAULT 0;
                    ALTER TABLE titles ADD COLUMN prompt_id TEXT;
                    """)
            }
            if version < 11 {
                try database.execute(Self.approvalAuditTables)
            }
            if version < 12 {
                try database.execute(Self.approvalPendingTable)
            }
            try database.execute("PRAGMA user_version = \(Self.schemaVersion)")
        }
    }

    private func createVersion2() throws {
        try database.execute(
            """
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
        // Version 2: the user's on/off choices for installed plugins.
        try database.execute(
            "CREATE TABLE IF NOT EXISTS plugin_choices (plugin_id TEXT PRIMARY KEY, enabled INTEGER NOT NULL)")
    }

    // MARK: - Meta

    func meta(_ key: String) throws -> String? {
        try database.query("SELECT value FROM meta WHERE key = ?", .text(key)).first?.first?.text
    }

    func setMeta(_ key: String, _ value: String?) throws {
        if let value {
            try database.run(
                "INSERT INTO meta (key, value) VALUES (?, ?) ON CONFLICT(key) DO UPDATE SET value = excluded.value",
                .text(key), .text(value))
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
                try database.run(
                    "INSERT INTO agents (id, spec) VALUES (?, ?)", .text(agent.id),
                    .text(String(decoding: try encoder.encode(agent), as: UTF8.self)))
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
            INSERT INTO sessions (id, agent_id, agent_session_id, cwd, parent_id, origin, title, created_at, last_activity, last_stop_reason, queue_paused, mcp_servers, meta, config_choices, adopted)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            .text(session.id.description), .text(session.agentID), .text(session.agentSessionID?.rawValue),
            .text(session.cwd),
            .text(session.parentID?.description), .text(session.origin.rawValue), .text(session.title),
            .date(session.createdAt),
            .date(session.lastActivity), .text(session.lastStopReason), .bool(session.isQueuePaused),
            try JSONColumn.encode(session.mcpServers), try session.meta.map(JSONColumn.encode) ?? .null,
            try JSONColumn.encode(session.configChoices), .bool(session.isAdopted)
        )
    }

    func updateSession(_ session: StoredSession) throws {
        try database.run(
            """
            UPDATE sessions SET agent_session_id = ?, title = ?, last_activity = ?, last_stop_reason = ?, queue_paused = ?,
                config_choices = ?, mcp_servers = ?
            WHERE id = ?
            """,
            .text(session.agentSessionID?.rawValue), .text(session.title), .date(session.lastActivity),
            .text(session.lastStopReason),
            .bool(session.isQueuePaused), try JSONColumn.encode(session.configChoices),
            try JSONColumn.encode(session.mcpServers), .text(session.id.description)
        )
    }

    func deleteSession(_ id: HostSessionID) throws {
        try database.run("DELETE FROM sessions WHERE id = ?", .text(id.description))
    }

    func sessions() throws -> [StoredSession] {
        try database.query(
            """
            SELECT id, agent_id, agent_session_id, cwd, parent_id, origin, title, created_at, last_activity, last_stop_reason, queue_paused, mcp_servers, meta, config_choices, adopted
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
            INSERT INTO turns (session_id, request_id, text, kind, echo, started_at, attempts, extra) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(session_id) DO UPDATE SET request_id = excluded.request_id, text = excluded.text, kind = excluded.kind,
                echo = excluded.echo, started_at = excluded.started_at, attempts = excluded.attempts, extra = excluded.extra
            """,
            .text(turn.sessionID.description), .text(turn.requestID.uuidString), .text(turn.text),
            .text(turn.kind.rawValue),
            .bool(turn.prompt.isEchoed), .date(turn.startedAt), .integer(Int64(turn.attempts)),
            try JSONColumn.encode(turn.prompt.extras)
        )
    }

    func finishTurn(_ sessionID: HostSessionID) throws {
        try database.run("DELETE FROM turns WHERE session_id = ?", .text(sessionID.description))
    }

    func unfinishedTurns() throws -> [UnfinishedTurn] {
        try database.query("SELECT session_id, request_id, text, kind, echo, started_at, attempts, extra FROM turns")
            .compactMap(UnfinishedTurn.init(row:))
    }

    // MARK: - Queue

    /// Replaces a session's queue. Queues are a handful of messages, so writing the whole thing keeps
    /// the order trivially right.
    func setQueue(_ items: [StoredQueueItem], for sessionID: HostSessionID) throws {
        try database.run("DELETE FROM queue WHERE session_id = ?", .text(sessionID.description))
        for (position, item) in items.enumerated() {
            try database.run(
                "INSERT INTO queue (session_id, position, id, text, echo, steering, extra) VALUES (?, ?, ?, ?, ?, ?, ?)",
                .text(sessionID.description), .integer(Int64(position)), .text(item.prompt.id.uuidString),
                .text(item.prompt.text),
                .bool(item.prompt.isEchoed), .bool(item.isSteering), try JSONColumn.encode(item.prompt.extras)
            )
        }
    }

    func queue(for sessionID: HostSessionID) throws -> [StoredQueueItem] {
        try database.query(
            "SELECT id, text, echo, steering, extra FROM queue WHERE session_id = ? ORDER BY position",
            .text(sessionID.description)
        ).compactMap { row in
            guard let id = row[0].text.flatMap(UUID.init(uuidString:)), let text = row[1].text else { return nil }
            let prompt = OutgoingPrompt(
                id: id, text: text, isEchoed: row[2].bool, extras: JSONColumn.decode(OutgoingPrompt.Extras.self, row[4])
            )
            return StoredQueueItem(prompt: prompt, isSteering: row[3].bool)
        }
    }

    // MARK: - Prompt requests

    /// What a prompt request id was delivered as, if it's been seen before.
    func delivery(for requestID: UUID) throws -> PromptDelivery? {
        try database.query("SELECT delivery FROM requests WHERE request_id = ?", .text(requestID.uuidString)).first?
            .first?.text.map { PromptDelivery(rawValue: $0) ?? .unknown }
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
        try database.run(
            "DELETE FROM approvals WHERE session_id = ? AND tool_call_id = ?", .text(sessionID.description),
            .text(toolCallID))
    }

    func removeApprovals(sessionID: HostSessionID) throws {
        try database.run("DELETE FROM approvals WHERE session_id = ?", .text(sessionID.description))
    }

    /// Approvals that were waiting when the host last stopped, by session. Their requests died with
    /// the agent; the agent asks again once the session resumes.
    func approvals() throws -> [HostSessionID: [String]] {
        var approvals: [HostSessionID: [String]] = [:]
        for row in try database.query(
            "SELECT session_id, tool_call_id FROM approvals UNION ALL SELECT session_id, tool_call_id FROM approval_pending"
        ) {
            guard let session = row[0].text.flatMap(UUID.init(uuidString:)).map(HostSessionID.init),
                let toolCall = row[1].text
            else { continue }
            approvals[session, default: []].append(toolCall)
        }
        return approvals
    }

    // MARK: - Activity

    /// Adds an entry; `entry.id` is ignored and the stored entry, numbered, comes back.
    @discardableResult
    func appendActivity(_ entry: ActivityEntry) throws -> ActivityEntry {
        try database.run(
            """
            INSERT INTO activity (at, session_id, kind, subject, detail, recovery, agent_id, agent_session_id, previous_run)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            .date(entry.at), .text(entry.sessionID?.description), .text(entry.kind.rawValue), .text(entry.subject),
            .text(entry.detail), try entry.recovery.map(JSONColumn.encode) ?? .null, .text(entry.agentID),
            .text(entry.agentSessionID?.rawValue), .text(entry.previousRun?.rawValue)
        )
        var stored = entry
        stored.id = database.lastInsertRowID
        return stored
    }

    /// Entries after `id`; the record of commands clients ran only with `includeCommands`.
    func activity(after id: Int64?, limit: Int, includeCommands: Bool = false) throws -> [ActivityEntry] {
        try database.query(
            """
            SELECT id, at, session_id, kind, subject, detail, recovery, agent_id, agent_session_id, previous_run
            FROM activity WHERE id > ? AND (? OR kind != ?) ORDER BY id LIMIT ?
            """,
            .integer(id ?? 0), .bool(includeCommands), .text(ActivityEntry.Kind.commandRun.rawValue),
            .integer(Int64(limit))
        ).compactMap { row in
            guard let id = row[0].integer, let at = row[1].date, let kind = row[3].text else { return nil }
            return ActivityEntry(
                id: id, at: at, sessionID: row[2].text.flatMap(UUID.init(uuidString:)).map(HostSessionID.init),
                agentID: row[7].text, agentSessionID: row[8].text.map(SessionID.init),
                kind: ActivityEntry.Kind(rawValue: kind) ?? .unknown, subject: row[4].text, detail: row[5].text,
                recovery: JSONColumn.decode(RecoveryNote.self, row[6]),
                previousRun: row[9].text.map { ActivityEntry.RunEnding(rawValue: $0) ?? .unknown }
            )
        }
    }

    /// Forgets entries of one kind older than `date`: the record of commands, which would otherwise
    /// grow with every `git status` a client runs.
    func pruneActivity(_ kind: ActivityEntry.Kind, olderThan date: Date) throws {
        try database.run("DELETE FROM activity WHERE kind = ? AND at < ?", .text(kind.rawValue), .date(date))
    }

    // MARK: - Projects

    func projects() throws -> [HostProject] {
        try database.query("SELECT path, added_at FROM projects ORDER BY path").compactMap { row in
            guard let path = row[0].text, let addedAt = row[1].date else { return nil }
            return HostProject(path: path, addedAt: addedAt)
        }
    }

    /// Adding a project that's listed already keeps it as it was.
    func addProject(_ project: HostProject) throws {
        try database.run(
            "INSERT OR IGNORE INTO projects (path, added_at) VALUES (?, ?)", .text(project.path),
            .date(project.addedAt))
    }

    func removeProject(_ path: String) throws {
        try database.run("DELETE FROM projects WHERE path = ?", .text(path))
    }

    // MARK: - Plugins

    func pluginChoices() throws -> [String: Bool] {
        var choices: [String: Bool] = [:]
        for row in try database.query("SELECT plugin_id, enabled FROM plugin_choices") {
            if let id = row[0].text { choices[id] = row[1].bool }
        }
        return choices
    }

    func setPluginChoice(_ pluginID: String, enabled: Bool) throws {
        try database.run(
            "INSERT INTO plugin_choices (plugin_id, enabled) VALUES (?, ?) ON CONFLICT(plugin_id) DO UPDATE SET enabled = excluded.enabled",
            .text(pluginID), .bool(enabled))
    }

    // MARK: - Inspection, for tests

    func pragma(_ name: String) throws -> String? {
        let value = try database.query("PRAGMA \(name)").first?.first
        return value?.text ?? value?.integer.map(String.init)
    }
}
