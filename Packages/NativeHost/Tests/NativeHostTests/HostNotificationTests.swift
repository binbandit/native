import ACP
import Foundation
import NativeHostClient
import NativeHostProtocol
import Testing

@testable import NativeHost

/// Notifications as host events (docs/durability.md, "Notifications"): posted whether or not a
/// client is there, kept in a bounded backlog, cleared on every client when one acknowledges them,
/// and still right after the host restarts.
@Suite("Host notifications", .serialized, .timeLimit(.minutes(1)))
struct HostNotificationTests {
    @Test("A turn that finishes with no client connected leaves a notification for the next one")
    func postedWithNoClient() async throws {
        let harness = try HostHarness()
        try harness.start()
        let first = try await harness.connect()
        let session = try await first.client.newSession(
            NewSessionParams(agentID: "fake", cwd: harness.root.path(percentEncoded: false))
        ).id
        _ = try await first.client.prompt(PromptParams(sessionID: session, text: "slow 3"))
        await first.stop()

        try await Task.sleep(for: .seconds(2))
        let second = try await harness.connect()
        let list = try await second.client.notifications()
        let finished = try #require(list.notifications.first { $0.kind == .turnFinished })
        #expect(finished.sessionID == session)
        #expect(finished.state == .active)
        #expect(finished.agentName == "Fake Agent")
        #expect((finished.duration ?? 0) >= 0.6)
        #expect(list.active.map(\.id) == [finished.id])
        #expect(list.latestID == finished.id)
        await second.stop()
    }

    @Test("Acknowledging on one client clears it on another; acting answers on the host")
    func acknowledgedAcrossClients() async throws {
        let harness = try HostHarness()
        try harness.start()
        let first = try await harness.connect()
        let second = try await harness.connect()
        let heard = NotificationLog()
        await heard.listen(to: second.client)
        let session = try await first.client.newSession(
            NewSessionParams(agentID: "fake", cwd: harness.root.path(percentEncoded: false), attach: true)
        ).id

        _ = try await first.client.prompt(PromptParams(sessionID: session, text: "permission please"))
        let permission = try await heard.waitForPosted { $0.kind == .permission }
        #expect(permission.detail == "Write notes.txt")
        #expect(permission.actions == [.allow, .reject])
        #expect(permission.allowOptionID.flatMap(UUID.init(uuidString:)) != nil)
        try await first.client.acknowledgeNotifications([permission.id])
        let acknowledged = try await heard.waitForCleared { $0.ids == [permission.id] }
        #expect(acknowledged.state == .acknowledged)
        #expect(acknowledged.by == "tests")

        // Still waiting in the task: the other client can answer from its notification.
        #expect(try await second.client.act(on: permission.id, .allow) == .done)
        try await first.wait("the turn") { await $0.agentText(session).contains("permission: allow") }
        #expect(try await first.client.act(on: permission.id, .reject) == .alreadyAnswered)

        _ = try await first.client.prompt(PromptParams(sessionID: session, text: "question please"))
        let question = try await heard.waitForPosted { $0.kind == .question }
        #expect(question.actions == [.reply])
        #expect(try await second.client.act(on: question.id, .reply, text: "blue") == .done)
        let resolved = try await heard.waitForCleared { $0.ids == [question.id] }
        #expect(resolved.state == .resolved)
        try await first.wait("the answer") { await $0.agentText(session).contains("question: accept blue") }
        await first.stop()
        await second.stop()
    }

    @Test("After a host restart, ids carry on, what was seen stays seen, and dead approvals are over")
    func survivesHostRestart() async throws {
        let harness = try HostHarness()
        try harness.start()
        let first = try await harness.connect()
        let session = try await first.client.newSession(
            NewSessionParams(agentID: "fake", cwd: harness.root.path(percentEncoded: false), attach: true)
        ).id
        _ = try await first.client.prompt(PromptParams(sessionID: session, text: "hello"))
        try await first.wait("the turn") { await $0.turnsEnded(session) == ["end_turn"] }
        let finished = try #require(try await first.client.notifications().notifications.last)
        #expect(finished.kind == .turnFinished)
        try await first.client.acknowledgeNotifications([finished.id])
        _ = try await first.client.prompt(PromptParams(sessionID: session, text: "permission please"))
        // The session event is sent before the notification is stored. Crash only after that write.
        try #require(
            await first.client.events.contains { event in
                guard case .notificationPosted(let notification) = event else { return false }
                return notification.kind == .permission && notification.sessionID == session
            })
        await first.stop()

        harness.kill()
        try harness.start()
        let second = try await harness.connect()
        try await second.wait("the recovery") { recorder in
            (try? await recorder.client.notifications().notifications.contains { $0.kind == .recovered }) == true
        }
        let list = try await second.client.notifications()
        let byID = Dictionary(uniqueKeysWithValues: list.notifications.map { ($0.id, $0) })
        #expect(byID[finished.id]?.state == .acknowledged)
        let permission = try #require(list.notifications.first { $0.kind == .permission })
        #expect(permission.id > finished.id)
        #expect(permission.state == .resolved)
        let recovered = try #require(list.notifications.first { $0.kind == .recovered })
        #expect(recovered.id > permission.id)
        #expect(recovered.recovery?.cause == .hostStopped)
        #expect(!list.active.contains { $0.waitsOnUser })
        #expect(try await second.client.act(on: permission.id, .allow) == .alreadyAnswered)
        await second.stop()
    }

    @Test("A notification names its task as clients do: the user's title over the first message")
    func namedAsClientsName() async throws {
        let harness = try HostHarness()
        try harness.start()
        let recorder = try await harness.connect()
        let session = try await recorder.client.newSession(
            NewSessionParams(agentID: "fake", cwd: harness.root.path(percentEncoded: false), attach: true)
        ).id
        try await recorder.client.setSessionTitle(
            SetSessionTitleParams(sessionID: session, title: "Uploads", source: .user))
        _ = try await recorder.client.prompt(PromptParams(sessionID: session, text: "hello"))
        try await recorder.wait("the turn") { await $0.turnsEnded(session) == ["end_turn"] }
        let finished = try #require(try await recorder.client.notifications().notifications.last)
        #expect(finished.kind == .turnFinished)
        #expect(finished.title == "Uploads")
        await recorder.stop()
    }

    @Test("The backlog keeps the newest notifications, numbered on from those it dropped")
    func backlogIsBounded() throws {
        let url = FileManager.default.temporaryDirectory.appending(
            path: "native-host-notes-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = try HostStore(url: url)
        let session = HostSessionID()
        for index in 1...25 {
            _ = try store.addNotification(
                HostNotification(
                    kind: .turnFinished, sessionID: session, agentID: "fake", agentName: "Fake Agent",
                    agentSessionID: SessionID("s"), title: "Task \(index)"),
                keeping: 10)
        }
        let kept = try store.notifications(after: nil, limit: 100)
        #expect(kept.map(\.id) == Array(16...25))
        #expect(kept.last?.title == "Task 25")
        #expect(try store.latestNotificationID() == 25)
        #expect(try store.activeNotifications().count == 10)
    }
}

/// What a client heard about notifications, in order.
private actor NotificationLog {
    private(set) var posted: [HostNotification] = []
    private(set) var cleared: [NotificationsClearedMessage] = []

    func listen(to client: NativeHostClient) async {
        await client.addEventHandler { [weak self] event in
            await self?.record(event)
        }
    }

    private func record(_ event: NativeHostClient.Event) {
        switch event {
        case .notificationPosted(let notification): posted.append(notification)
        case .notificationsCleared(let message): cleared.append(message)
        default: break
        }
    }

    func waitForPosted(_ matches: @Sendable (HostNotification) -> Bool) async throws -> HostNotification {
        try await poll("a notification") { posted.first(where: matches) }
    }

    func waitForCleared(
        _ matches: @Sendable (NotificationsClearedMessage) -> Bool
    ) async throws
        -> NotificationsClearedMessage
    {
        try await poll("a clearing") { cleared.first(where: matches) }
    }

    private func poll<Value>(_ what: String, _ find: () async -> Value?) async throws -> Value {
        let deadline = ContinuousClock.now + .seconds(20)
        while ContinuousClock.now < deadline {
            if let value = await find() { return value }
            try await Task.sleep(for: .milliseconds(50))
        }
        Issue.record("Timed out waiting for \(what)")
        throw CancellationError()
    }
}
