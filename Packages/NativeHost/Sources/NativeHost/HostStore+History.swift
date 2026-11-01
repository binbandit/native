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
        // The source has its own items; a watermark that was at the head moves with them.
        try database.run(
            "UPDATE history_participants SET seen = ? WHERE history_id = ? AND ordinal = ? AND seen = ?",
            .integer(Int64(head + items.count)), .text(history.description), .integer(Int64(source)),
            .integer(Int64(head)))
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

    /// Whether the turn has an item of `kind` already, or any item at all without one: a retry or a
    /// recovery records a turn again, and must not add it twice.
    func hasHistoryItem(turn: UUID, kind: String? = nil, in history: TaskHistoryID) throws -> Bool {
        try !database.query(
            "SELECT 1 FROM history_items WHERE history_id = ? AND turn = ? AND (? IS NULL OR kind = ?) LIMIT 1",
            .text(history.description), .text(turn.uuidString), .text(kind), .text(kind)
        ).isEmpty
    }

    /// The newest item of `kind`, to tell whether something changed since it was recorded.
    func lastHistoryBody(kind: String, in history: TaskHistoryID) throws -> TaskHistoryItem.Body? {
        try database.query(
            "SELECT body FROM history_items WHERE history_id = ? AND kind = ? ORDER BY seq DESC LIMIT 1",
            .text(history.description), .text(kind)
        ).first.flatMap { JSONColumn.decode(TaskHistoryItem.Body.self, $0[0]) }
    }

    /// Adds an agent session to a history as its next participant. An agent session that had
    /// started a history of its own with nothing in it (a change of agent's new conversation) leaves
    /// it; one whose history has items can't join another. Inside the caller's transaction.
    func joinHistory(
        _ history: TaskHistoryID, agentID: String, agentSessionID: SessionID, model: String?, at date: Date = .now
    ) throws -> TaskHistoryParticipant? {
        if let (current, participant) = try historyParticipant(agentID: agentID, agentSessionID: agentSessionID) {
            if current == history { return participant }
            guard try historyHead(current) == 0, try historyParticipants(of: current).count == 1 else { return nil }
            try database.run("DELETE FROM histories WHERE id = ?", .text(current.description))
        }
        let next =
            try database.query(
                "SELECT COALESCE(MAX(ordinal), 0) + 1 FROM history_participants WHERE history_id = ?",
                .text(history.description)
            ).first?.first?.integer ?? 1
        let participant = TaskHistoryParticipant(
            ordinal: Int(next), agentID: agentID, agentSessionID: agentSessionID, model: model, joinedAt: date)
        try insert(participant, into: history)
        return participant
    }

    /// A joined agent session that never took a message (its change of agent was undone) leaves the
    /// history, with the transfers prepared for it.
    func leaveHistoryIfUnused(agentID: String, agentSessionID: SessionID) throws {
        try transaction {
            guard let (history, participant) = try historyParticipant(agentID: agentID, agentSessionID: agentSessionID),
                participant.ordinal > 1,
                try database.query(
                    "SELECT 1 FROM history_items WHERE history_id = ? AND source = ? LIMIT 1",
                    .text(history.description), .integer(Int64(participant.ordinal))
                ).isEmpty
            else { return }
            try database.run(
                "DELETE FROM history_transfers WHERE history_id = ? AND target = ?", .text(history.description),
                .integer(Int64(participant.ordinal)))
            try database.run(
                "DELETE FROM history_participants WHERE history_id = ? AND ordinal = ?", .text(history.description),
                .integer(Int64(participant.ordinal)))
        }
    }

    func insertTransfer(_ transfer: TaskHistoryTransfer, into history: TaskHistoryID, receipt: JSONValue? = nil) throws
    {
        try database.run(
            """
            INSERT INTO history_transfers (id, history_id, source_history, target, from_seq, through_seq, covered, strategy, state, request_id, receipt, created_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            .text(transfer.id.uuidString), .text(history.description), .text(transfer.sourceHistory.description),
            .integer(Int64(transfer.target)), .integer(Int64(transfer.from)), .integer(Int64(transfer.through)),
            try JSONColumn.encode(transfer.conveyed), .text(transfer.strategy.rawValue), .text(transfer.state.rawValue),
            .text(transfer.requestID?.uuidString), try receipt.map(JSONColumn.encode) ?? .null,
            .date(transfer.createdAt))
    }

    func historyTransfers(of history: TaskHistoryID) throws -> [TaskHistoryTransfer] {
        try database.query(
            """
            SELECT id, source_history, target, from_seq, through_seq, covered, strategy, state, request_id, created_at
            FROM history_transfers WHERE history_id = ? ORDER BY created_at, rowid
            """, .text(history.description)
        ).compactMap { row in
            guard let id = row[0].text.flatMap(UUID.init(uuidString:)),
                let source = row[1].text.flatMap(UUID.init(uuidString:)), let target = row[2].integer,
                let from = row[3].integer, let through = row[4].integer, let createdAt = row[9].date
            else { return nil }
            return TaskHistoryTransfer(
                id: id, sourceHistory: TaskHistoryID(source), target: Int(target), from: Int(from),
                through: Int(through), conveyed: JSONColumn.decode([ClosedRange<Int>].self, row[5]) ?? [],
                strategy: row[6].text.flatMap(TaskHistoryTransfer.Strategy.init(rawValue:)) ?? .unknown,
                state: row[7].text.flatMap(TaskHistoryTransfer.State.init(rawValue:)) ?? .unknown,
                requestID: row[8].text.flatMap(UUID.init(uuidString:)), createdAt: createdAt)
        }
    }

    /// The target's prepared transfers go with the message `requestID`.
    func sendHistoryTransfers(in history: TaskHistoryID, to target: Int, with requestID: UUID) throws {
        try database.run(
            """
            UPDATE history_transfers SET state = 'sent', request_id = ?
            WHERE history_id = ? AND target = ? AND state = 'prepared'
            """, .text(requestID.uuidString), .text(history.description), .integer(Int64(target)))
    }

    /// The agent answered the message `requestID`, so what went with it arrived: its transfers are
    /// delivered and the target's watermark moves over what they conveyed.
    func deliverHistoryTransfers(in history: TaskHistoryID, to target: Int, with requestID: UUID) throws {
        try database.run(
            """
            UPDATE history_transfers SET state = 'delivered'
            WHERE history_id = ? AND target = ? AND request_id = ? AND state = 'sent'
            """, .text(history.description), .integer(Int64(target)), .text(requestID.uuidString))
        try updateWatermark(of: target, in: history)
    }

    /// Moves a participant's watermark over everything now in its context.
    func updateWatermark(of participant: Int, in history: TaskHistoryID) throws {
        guard let current = try historyParticipants(of: history).first(where: { $0.ordinal == participant }) else {
            return
        }
        let conveyed = TaskHistoryCoverage.conveyed(
            to: participant, by: try historyTransfers(of: history), in: history)
        let seen = TaskHistoryCoverage.watermark(
            from: current.seen, over: try historyItems(of: history, after: current.seen, limit: .max),
            participant: participant, conveyed: conveyed)
        guard seen != current.seen else { return }
        try database.run(
            "UPDATE history_participants SET seen = ? WHERE history_id = ? AND ordinal = ?", .integer(Int64(seen)),
            .text(history.description), .integer(Int64(participant)))
    }

    /// The model a participant's agent session runs with now, when it changed since it was recorded.
    func setHistoryModel(_ model: String, of participant: Int, in history: TaskHistoryID) throws {
        try database.run(
            "UPDATE history_participants SET model = ? WHERE history_id = ? AND ordinal = ? AND model IS NOT ?",
            .text(model), .text(history.description), .integer(Int64(participant)), .text(model))
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
