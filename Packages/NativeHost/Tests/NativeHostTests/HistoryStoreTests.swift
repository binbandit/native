import ACP
import Foundation
import NativeHostProtocol
import Testing

@testable import NativeHost

/// The task history tables (docs/decisions/2026-11-01-one-task-history.md): numbering, finding a
/// history again by agent session, and retention.
@Suite("Task history store")
struct HistoryStoreTests {
    let url = FileManager.default.temporaryDirectory.appending(path: "native-history-\(UUID().uuidString).sqlite")

    @Test("A version 13 store gains the history tables and keeps its sessions")
    func migratesFromVersion13() throws {
        let session = StoredSession(
            id: HostSessionID(), agentID: "fake", agentSessionID: SessionID("s"), cwd: "/tmp", parentID: nil,
            origin: .user)
        do {
            let store = try HostStore(url: url)
            try store.insertSession(session)
            try store.database.execute(
                """
                DROP TABLE history_transfers;
                DROP TABLE history_items;
                DROP TABLE history_participants;
                DROP TABLE histories;
                PRAGMA user_version = 13;
                """)
        }
        let migrated = try HostStore(url: url)
        #expect(try migrated.pragma("user_version") == "14")
        #expect(try migrated.sessions().map(\.id) == [session.id])
        let (id, _) = try migrated.createHistory(cwd: "/tmp", agentID: "fake", agentSessionID: SessionID("s"))
        #expect(try migrated.historyHead(id) == 0)
    }

    @Test("Items are numbered on from the newest, without gaps, and survive reopening")
    func numbering() throws {
        let id: TaskHistoryID
        do {
            let store = try HostStore(url: url)
            (id, _) = try store.createHistory(cwd: "/tmp", agentID: "claude", agentSessionID: SessionID("a"))
            let turn = UUID()
            let first = try store.transaction {
                try store.appendHistoryItems(
                    [.user(.init(text: "fix the test")), .agent("Done.")], to: id, source: 1, turn: turn,
                    at: Date(timeIntervalSince1970: 100))
            }
            #expect(first.map(\.seq) == [1, 2])
            let second = try store.transaction {
                try store.appendHistoryItems(
                    [.turnEnded(stopReason: "end_turn")], to: id, source: 1, turn: turn, at: nil)
            }
            #expect(second.map(\.seq) == [3])
        }
        let reopened = try HostStore(url: url)
        #expect(try reopened.historyHead(id) == 3)
        let items = try reopened.historyItems(of: id, after: 1, limit: 10)
        #expect(items.map(\.seq) == [2, 3])
        #expect(items.first?.body == .agent("Done."))
        #expect(items.last?.at == nil)
        #expect(try reopened.historyItems(of: id, after: 0, through: 1, limit: 10).map(\.seq) == [1])
    }

    @Test("A body kind a newer host wrote keeps its place and reads as unknown")
    func unknownKind() throws {
        let store = try HostStore(url: url)
        let (id, _) = try store.createHistory(cwd: "/tmp", agentID: "claude", agentSessionID: SessionID("a"))
        try store.database.run(
            "INSERT INTO history_items (history_id, seq, source, kind, body) VALUES (?, 1, 1, 'fork', ?)",
            .text(id.description), .text(#"{"type":"fork","from":3}"#))
        #expect(try store.historyItems(of: id, after: 0, limit: 10).map(\.body) == [.unknown(kind: "fork")])
    }

    @Test("An agent session is found in its history, and moves with an unsaved replacement")
    func lookup() throws {
        let store = try HostStore(url: url)
        let (id, participant) = try store.createHistory(
            cwd: "/tmp", agentID: "claude", agentSessionID: SessionID("a"), model: "haiku",
            // Whole seconds: the store keeps dates as seconds since 1970, which rounds `now`.
            at: Date(timeIntervalSince1970: 1_000))
        #expect(participant.ordinal == 1)
        let found = try #require(try store.historyParticipant(agentID: "claude", agentSessionID: SessionID("a")))
        #expect(found.0 == id)
        #expect(found.1 == participant)
        // The same ACP session id under another agent is another session.
        #expect(try store.historyParticipant(agentID: "codex", agentSessionID: SessionID("a")) == nil)
        try store.replaceHistoryAgentSession(agentID: "claude", old: SessionID("a"), new: SessionID("b"))
        #expect(try store.historyParticipant(agentID: "claude", agentSessionID: SessionID("a")) == nil)
        #expect(try store.historyParticipant(agentID: "claude", agentSessionID: SessionID("b"))?.0 == id)
    }

    @Test("Deleting the last agent session of a task deletes its history")
    func retention() throws {
        let store = try HostStore(url: url)
        let (id, _) = try store.createHistory(cwd: "/tmp", agentID: "claude", agentSessionID: SessionID("a"))
        try store.database.run(
            """
            INSERT INTO history_participants (history_id, ordinal, agent_id, agent_session_id, joined_at)
            VALUES (?, 2, 'codex', 'b', 0)
            """, .text(id.description))
        try store.transaction {
            try store.appendHistoryItems([.agent("hello")], to: id, source: 1, turn: nil, at: nil)
        }
        try store.forgetHistoryParticipant(agentID: "claude", agentSessionID: SessionID("a"))
        #expect(try store.historyHead(id) == 1)
        #expect(try store.historyParticipants(of: id).map(\.isGone) == [true, false])
        try store.forgetHistoryParticipant(agentID: "codex", agentSessionID: SessionID("b"))
        #expect(try store.historyHead(id) == nil)
        #expect(try store.historyItems(of: id, after: 0, limit: 10).isEmpty)
        #expect(try store.historyParticipants(of: id).isEmpty)
    }
}
