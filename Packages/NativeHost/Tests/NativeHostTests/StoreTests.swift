import ACP
import Foundation
import NativeHostProtocol
import Testing

@testable import NativeHost

@Suite("Host store")
struct StoreTests {
    let url = FileManager.default.temporaryDirectory.appending(path: "native-host-store-\(UUID().uuidString).sqlite")

    @Test("Commits are fully synced, with a write-ahead log")
    func durabilitySettings() throws {
        let store = try HostStore(url: url)
        #expect(try store.pragma("journal_mode") == "wal")
        // 2 is FULL: every commit is fsynced, not just every checkpoint.
        #expect(try store.pragma("synchronous") == "2")
        #expect(try store.pragma("fullfsync") == "1")
    }

    @Test("A turn, its queue and its request id survive the store being reopened")
    func survivesReopen() throws {
        let session = StoredSession(
            id: HostSessionID(), agentID: "fake", agentSessionID: SessionID("s1"), cwd: "/tmp", parentID: nil,
            origin: .user, createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            meta: .object(["plugin": .string("x")]), configChoices: ["model": "large"], isAdopted: true)
        let turn = UnfinishedTurn(
            sessionID: session.id,
            prompt: OutgoingPrompt(
                text: "look at this",
                content: [.text("look at this"), .resourceLink(uri: "file:///a.txt", name: "a.txt")],
                attachments: [EchoAttachment(name: "a.png", imageBase64: "AAAA")],
                preamble: PromptPreambleSpec(
                    marker: PreambleMarker(id: "plan", label: "Plan mode"), instructions: "Plan."),
                origin: .task),
            kind: .prompt, startedAt: Date(timeIntervalSince1970: 1_700_000_000))
        let queued = [
            StoredQueueItem(prompt: OutgoingPrompt(text: "first"), isSteering: false),
            StoredQueueItem(
                prompt: OutgoingPrompt(text: "second", attachments: [EchoAttachment(name: "b.txt")], isEchoed: false),
                isSteering: true),
        ]
        do {
            let store = try HostStore(url: url)
            try store.insertSession(session)
            try store.transaction {
                try store.beginTurn(turn)
                try store.recordDelivery(.prompted, for: turn.requestID, in: session.id)
                try store.setQueue(queued, for: session.id)
            }
        }
        let reopened = try HostStore(url: url)
        #expect(try reopened.sessions() == [session])
        #expect(try reopened.unfinishedTurns() == [turn])
        #expect(try reopened.queue(for: session.id) == queued)
        #expect(try reopened.delivery(for: turn.requestID) == .prompted)
        #expect(try reopened.delivery(for: UUID()) == nil)
    }

    @Test("Version 8 stores gain durable settings for closed sessions")
    func migratesClosedSessionConfig() throws {
        do {
            let store = try HostStore(url: url)
            try store.database.execute(
                """
                DROP TABLE closed_session_config;
                ALTER TABLE titles DROP COLUMN retry_count;
                ALTER TABLE titles DROP COLUMN prompt_id;
                PRAGMA user_version = 8;
                """)
        }
        let session = StoredSession(
            id: HostSessionID(), agentID: "fake", agentSessionID: SessionID("saved"), cwd: "/tmp",
            parentID: nil, origin: .user, configChoices: ["model": "beta", "effort": "high"])
        do {
            let migrated = try HostStore(url: url)
            try migrated.keepClosedSessionConfig(session)
        }
        let reopened = try HostStore(url: url)
        #expect(
            try reopened.closedSessionConfig(agentID: "fake", agentSessionID: SessionID("saved"))
                == session.configChoices)
        #expect(try reopened.closedSessionConfig(agentID: "other", agentSessionID: SessionID("saved")) == nil)
        try reopened.forgetClosedSessionConfig(agentID: "fake", agentSessionID: SessionID("saved"))
        #expect(try reopened.closedSessionConfig(agentID: "fake", agentSessionID: SessionID("saved")) == nil)
    }

    @Test("A failed transaction leaves nothing behind")
    func atomicTransactions() throws {
        let store = try HostStore(url: url)
        let session = StoredSession(
            id: HostSessionID(), agentID: "fake", agentSessionID: nil, cwd: "/tmp", parentID: nil, origin: .user)
        try store.insertSession(session)
        struct Interrupted: Error {}
        #expect(throws: Interrupted.self) {
            try store.transaction {
                try store.beginTurn(
                    UnfinishedTurn(sessionID: session.id, prompt: OutgoingPrompt(text: "x"), kind: .prompt))
                throw Interrupted()
            }
        }
        #expect(try store.unfinishedTurns().isEmpty)
    }

    @Test("Closing a session drops its turn, queue and approvals")
    func cascades() throws {
        let store = try HostStore(url: url)
        let session = StoredSession(
            id: HostSessionID(), agentID: "fake", agentSessionID: SessionID("s"), cwd: "/tmp", parentID: nil,
            origin: .user)
        try store.insertSession(session)
        try store.beginTurn(UnfinishedTurn(sessionID: session.id, prompt: OutgoingPrompt(text: "x"), kind: .prompt))
        try store.setQueue([StoredQueueItem(prompt: OutgoingPrompt(text: "y"), isSteering: false)], for: session.id)
        try store.addApproval(sessionID: session.id, toolCallID: "call", title: "Write")
        try store.deleteSession(session.id)
        #expect(try store.unfinishedTurns().isEmpty)
        #expect(try store.queue(for: session.id).isEmpty)
        #expect(try store.approvals().isEmpty)
    }

    @Test("The activity journal keeps recovery notes and what each entry is about")
    func activity() throws {
        let store = try HostStore(url: url)
        let note = RecoveryNote(
            cause: .hostStopped, action: .resumed, agentName: "Claude Code",
            interruptedAt: Date(timeIntervalSince1970: 1_000))
        let at = Date(timeIntervalSince1970: 2_000)
        let first = try store.appendActivity(
            ActivityEntry(id: 0, at: at, sessionID: nil, kind: .hostStarted, previousRun: .crashed))
        let second = try store.appendActivity(
            ActivityEntry(
                id: 0, at: at, sessionID: HostSessionID(), agentID: "claude", agentSessionID: SessionID("s9"),
                kind: .recovered, subject: "Claude Code", recovery: note))
        #expect(try store.activity(after: nil, limit: 10) == [first, second])
        #expect(try store.activity(after: first.id, limit: 10).first?.recovery == note)
        #expect(try store.activity(after: nil, limit: 10).first?.previousRun == .crashed)
    }

    @Test("A version 2 store gains the new columns and keeps what it had")
    func migratesFromVersion2() throws {
        let session = HostSessionID()
        do {
            let database = try SQLiteDatabase(url: url)
            try database.execute(
                """
                CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT NOT NULL);
                CREATE TABLE agents (id TEXT PRIMARY KEY, spec TEXT NOT NULL);
                CREATE TABLE sessions (id TEXT PRIMARY KEY, agent_id TEXT NOT NULL, agent_session_id TEXT,
                    cwd TEXT NOT NULL, parent_id TEXT, origin TEXT NOT NULL, title TEXT, created_at REAL NOT NULL,
                    last_activity REAL, last_stop_reason TEXT, queue_paused INTEGER NOT NULL DEFAULT 0,
                    mcp_servers TEXT NOT NULL DEFAULT '[]');
                CREATE TABLE turns (session_id TEXT PRIMARY KEY, request_id TEXT NOT NULL, text TEXT NOT NULL,
                    kind TEXT NOT NULL, echo INTEGER NOT NULL, started_at REAL NOT NULL, attempts INTEGER NOT NULL DEFAULT 0);
                CREATE TABLE queue (session_id TEXT NOT NULL, position INTEGER NOT NULL, id TEXT NOT NULL,
                    text TEXT NOT NULL, echo INTEGER NOT NULL, steering INTEGER NOT NULL DEFAULT 0,
                    PRIMARY KEY (session_id, position));
                CREATE TABLE requests (request_id TEXT PRIMARY KEY, session_id TEXT NOT NULL, delivery TEXT NOT NULL,
                    at REAL NOT NULL);
                CREATE TABLE approvals (session_id TEXT NOT NULL, tool_call_id TEXT NOT NULL, title TEXT,
                    requested_at REAL NOT NULL, PRIMARY KEY (session_id, tool_call_id));
                CREATE TABLE activity (id INTEGER PRIMARY KEY AUTOINCREMENT, at REAL NOT NULL, session_id TEXT,
                    kind TEXT NOT NULL, subject TEXT, detail TEXT, recovery TEXT);
                CREATE TABLE plugin_choices (plugin_id TEXT PRIMARY KEY, enabled INTEGER NOT NULL);
                PRAGMA user_version = 2;
                """)
            try database.run(
                "INSERT INTO sessions (id, agent_id, agent_session_id, cwd, origin, created_at) VALUES (?, ?, ?, ?, ?, ?)",
                .text(session.description), .text("fake"), .text("s1"), .text("/tmp"), .text("user"), .real(1_000))
            try database.run(
                "INSERT INTO queue (session_id, position, id, text, echo) VALUES (?, 0, ?, ?, 1)",
                .text(session.description), .text(UUID().uuidString), .text("waiting"))
        }
        let store = try HostStore(url: url)
        #expect(try store.pragma("user_version") == String(HostStore.schemaVersion))
        let migrated = try #require(try store.sessions().first)
        #expect(migrated.id == session)
        #expect(migrated.configChoices.isEmpty)
        #expect(try store.queue(for: session).map(\.prompt.text) == ["waiting"])
        #expect(try store.queue(for: session).first?.prompt.origin == .user)
    }
}
