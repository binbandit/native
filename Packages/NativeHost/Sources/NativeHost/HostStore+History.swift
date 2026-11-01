import ACP
import Foundation

// One task history (docs/decisions/2026-11-01-one-task-history.md). Items are append-only and
// numbered per history without gaps; a participant is found by its agent session, which is unique
// across histories, so a session the host closed and reopened finds its history again. A transfer
// names the history its items come from (`source_history`: this one, or a fork for merge-back), the
// range it considered, and the items it conveyed (`covered`): only those count as seen.
extension HostStore {
    static let historyTables = """
        CREATE TABLE IF NOT EXISTS histories (
            id TEXT PRIMARY KEY,
            cwd TEXT NOT NULL,
            created_at REAL NOT NULL,
            head INTEGER NOT NULL DEFAULT 0,
            lineage TEXT
        );
        CREATE TABLE IF NOT EXISTS history_participants (
            history_id TEXT NOT NULL REFERENCES histories(id) ON DELETE CASCADE,
            ordinal INTEGER NOT NULL,
            agent_id TEXT NOT NULL,
            agent_session_id TEXT NOT NULL,
            model TEXT,
            joined_at REAL NOT NULL,
            seen INTEGER NOT NULL DEFAULT 0,
            gone INTEGER NOT NULL DEFAULT 0,
            PRIMARY KEY (history_id, ordinal)
        );
        CREATE UNIQUE INDEX IF NOT EXISTS history_participants_agent_session
            ON history_participants(agent_id, agent_session_id);
        CREATE TABLE IF NOT EXISTS history_items (
            history_id TEXT NOT NULL REFERENCES histories(id) ON DELETE CASCADE,
            seq INTEGER NOT NULL,
            source INTEGER NOT NULL,
            turn TEXT,
            kind TEXT NOT NULL,
            at REAL,
            body TEXT NOT NULL,
            PRIMARY KEY (history_id, seq)
        );
        CREATE INDEX IF NOT EXISTS history_items_turn ON history_items(history_id, turn);
        CREATE TABLE IF NOT EXISTS history_transfers (
            id TEXT PRIMARY KEY,
            history_id TEXT NOT NULL REFERENCES histories(id) ON DELETE CASCADE,
            source_history TEXT NOT NULL,
            target INTEGER NOT NULL,
            from_seq INTEGER NOT NULL,
            through_seq INTEGER NOT NULL,
            covered TEXT NOT NULL DEFAULT '[]',
            strategy TEXT NOT NULL,
            state TEXT NOT NULL,
            request_id TEXT,
            receipt TEXT,
            created_at REAL NOT NULL
        );
        """

    /// Starts a history with its first participant. Inside the caller's transaction, if any.
    func createHistory(
        cwd: String, agentID: String, agentSessionID: SessionID, model: String? = nil, at date: Date = .now
    ) throws -> (TaskHistoryID, TaskHistoryParticipant) {
        let id = TaskHistoryID()
        try database.run(
            "INSERT INTO histories (id, cwd, created_at) VALUES (?, ?, ?)", .text(id.description), .text(cwd),
            .date(date))
        let participant = TaskHistoryParticipant(
            ordinal: 1, agentID: agentID, agentSessionID: agentSessionID, model: model, joinedAt: date)
        try insert(participant, into: id)
        return (id, participant)
    }

    private func insert(_ participant: TaskHistoryParticipant, into history: TaskHistoryID) throws {
        try database.run(
            """
            INSERT INTO history_participants (history_id, ordinal, agent_id, agent_session_id, model, joined_at, seen, gone)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            """,
            .text(history.description), .integer(Int64(participant.ordinal)), .text(participant.agentID),
            .text(participant.agentSessionID.rawValue), .text(participant.model), .date(participant.joinedAt),
            .integer(Int64(participant.seen)), .bool(participant.isGone))
    }

    /// The history an agent session takes part in, and its place in it.
    func historyParticipant(
        agentID: String, agentSessionID: SessionID
    ) throws -> (
        TaskHistoryID, TaskHistoryParticipant
    )? {
        guard
            let row = try database.query(
                "SELECT history_id, \(Self.participantColumns) FROM history_participants WHERE agent_id = ? AND agent_session_id = ?",
                .text(agentID), .text(agentSessionID.rawValue)
            ).first,
            let id = row[0].text.flatMap(UUID.init(uuidString:)).map(TaskHistoryID.init),
            let participant = Self.participant(Array(row.dropFirst()))
        else { return nil }
        return (id, participant)
    }

    func historyParticipants(of history: TaskHistoryID) throws -> [TaskHistoryParticipant] {
        try database.query(
            "SELECT \(Self.participantColumns) FROM history_participants WHERE history_id = ? ORDER BY ordinal",
            .text(history.description)
        ).compactMap(Self.participant)
    }

    /// The newest item's `seq`, or nil when there's no such history.
    func historyHead(_ history: TaskHistoryID) throws -> Int? {
        try database.query("SELECT head FROM histories WHERE id = ?", .text(history.description)).first?.first?
            .integer.map(Int.init)
    }

    /// Adds items after the newest, numbered on from it, and returns them as stored. Run it inside a
    /// transaction so the numbering and the head move together.
    @discardableResult
    func appendHistoryItems(
        _ bodies: [TaskHistoryItem.Body], to history: TaskHistoryID, source: Int, turn: UUID?, at date: Date?
    ) throws -> [TaskHistoryItem] {
        guard !bodies.isEmpty, let head = try historyHead(history) else { return [] }
        let items = bodies.enumerated().map { offset, body in
            TaskHistoryItem(seq: head + offset + 1, source: source, turn: turn, at: date, body: body)
        }
        for item in items {
            try database.run(
                "INSERT INTO history_items (history_id, seq, source, turn, kind, at, body) VALUES (?, ?, ?, ?, ?, ?, ?)",
                .text(history.description), .integer(Int64(item.seq)), .integer(Int64(item.source)),
                .text(item.turn?.uuidString), .text(item.body.kind), .date(item.at), try JSONColumn.encode(item.body))
        }
        try database.run(
            "UPDATE histories SET head = ? WHERE id = ?", .integer(Int64(head + items.count)),
            .text(history.description))
        return items
    }

    /// Items after `after`, up to `through` when given, oldest first.
    func historyItems(
        of history: TaskHistoryID, after: Int, through: Int? = nil, limit: Int
    ) throws
        -> [TaskHistoryItem]
    {
        try database.query(
            """
            SELECT seq, source, turn, at, body FROM history_items
            WHERE history_id = ? AND seq > ? AND seq <= ? ORDER BY seq LIMIT ?
            """,
            .text(history.description), .integer(Int64(after)), .integer(Int64(through ?? Int.max)),
            .integer(Int64(limit))
        ).compactMap { row in
            guard let seq = row[0].integer, let source = row[1].integer,
                let body = JSONColumn.decode(TaskHistoryItem.Body.self, row[4])
            else { return nil }
            return TaskHistoryItem(
                seq: Int(seq), source: Int(source), turn: row[2].text.flatMap(UUID.init(uuidString:)), at: row[3].date,
                body: body)
        }
    }

    /// An unsaved agent session was replaced by a fresh one under the same host session.
    func replaceHistoryAgentSession(agentID: String, old: SessionID, new: SessionID) throws {
        try database.run(
            "UPDATE history_participants SET agent_session_id = ? WHERE agent_id = ? AND agent_session_id = ?",
            .text(new.rawValue), .text(agentID), .text(old.rawValue))
    }

    /// The agent deleted the session. Its items stay while another session of the task remains; the
    /// history goes with the last one.
    func forgetHistoryParticipant(agentID: String, agentSessionID: SessionID) throws {
        try transaction {
            guard let (history, _) = try historyParticipant(agentID: agentID, agentSessionID: agentSessionID) else {
                return
            }
            try database.run(
                "UPDATE history_participants SET gone = 1 WHERE agent_id = ? AND agent_session_id = ?",
                .text(agentID), .text(agentSessionID.rawValue))
            try database.run(
                """
                DELETE FROM histories WHERE id = ?
                    AND NOT EXISTS (SELECT 1 FROM history_participants WHERE history_id = ? AND gone = 0)
                """,
                .text(history.description), .text(history.description))
        }
    }

    private static let participantColumns = "ordinal, agent_id, agent_session_id, model, joined_at, seen, gone"

    private static func participant(_ row: [SQLiteDatabase.Value]) -> TaskHistoryParticipant? {
        guard let ordinal = row[0].integer, let agentID = row[1].text, let agentSessionID = row[2].text,
            let joinedAt = row[4].date
        else { return nil }
        return TaskHistoryParticipant(
            ordinal: Int(ordinal), agentID: agentID, agentSessionID: SessionID(agentSessionID), model: row[3].text,
            joinedAt: joinedAt, seen: Int(row[5].integer ?? 0), isGone: row[6].bool)
    }
}
