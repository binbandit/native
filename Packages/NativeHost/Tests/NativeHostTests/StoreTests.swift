import ACP
import Foundation
@testable import NativeHost
import NativeHostProtocol
import Testing

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
        let session = StoredSession(id: HostSessionID(), agentID: "fake", agentSessionID: SessionID("s1"), cwd: "/tmp", parentID: nil, origin: .user)
        let turn = UnfinishedTurn(sessionID: session.id, requestID: UUID(), text: "slow 5", kind: .prompt, echo: true, startedAt: Date(timeIntervalSince1970: 1_700_000_000))
        let queued = [StoredQueueItem(prompt: QueuedPrompt(text: "first"), isSteering: false), StoredQueueItem(prompt: QueuedPrompt(text: "second"), isSteering: true)]
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
        #expect(try reopened.sessions().map(\.id) == [session.id])
        #expect(try reopened.unfinishedTurns() == [turn])
        #expect(try reopened.queue(for: session.id) == queued)
        #expect(try reopened.delivery(for: turn.requestID) == .prompted)
        #expect(try reopened.delivery(for: UUID()) == nil)
    }

    @Test("A failed transaction leaves nothing behind")
    func atomicTransactions() throws {
        let store = try HostStore(url: url)
        let session = StoredSession(id: HostSessionID(), agentID: "fake", agentSessionID: nil, cwd: "/tmp", parentID: nil, origin: .user)
        try store.insertSession(session)
        struct Interrupted: Error {}
        #expect(throws: Interrupted.self) {
            try store.transaction {
                try store.beginTurn(UnfinishedTurn(sessionID: session.id, requestID: UUID(), text: "x", kind: .prompt, echo: true))
                throw Interrupted()
            }
        }
        #expect(try store.unfinishedTurns().isEmpty)
    }

    @Test("Closing a session drops its turn, queue and approvals")
    func cascades() throws {
        let store = try HostStore(url: url)
        let session = StoredSession(id: HostSessionID(), agentID: "fake", agentSessionID: SessionID("s"), cwd: "/tmp", parentID: nil, origin: .user)
        try store.insertSession(session)
        try store.beginTurn(UnfinishedTurn(sessionID: session.id, requestID: UUID(), text: "x", kind: .prompt, echo: true))
        try store.setQueue([StoredQueueItem(prompt: QueuedPrompt(text: "y"), isSteering: false)], for: session.id)
        try store.addApproval(sessionID: session.id, toolCallID: "call", title: "Write")
        try store.deleteSession(session.id)
        #expect(try store.unfinishedTurns().isEmpty)
        #expect(try store.queue(for: session.id).isEmpty)
        #expect(try store.approvals().isEmpty)
    }

    @Test("The activity journal keeps recovery notes")
    func activity() throws {
        let store = try HostStore(url: url)
        let note = RecoveryNote(cause: .hostStopped, action: .resumed, agentName: "Claude Code", interruptedAt: Date(timeIntervalSince1970: 1_000))
        let first = try store.appendActivity(.turnFinished, session: nil, subject: "Fix the build")
        let second = try store.appendActivity(.recovered, session: HostSessionID(), subject: "Claude Code", recovery: note)
        #expect(try store.activity(after: nil, limit: 10).map(\.id) == [first.id, second.id])
        #expect(try store.activity(after: first.id, limit: 10).first?.recovery == note)
    }
}
