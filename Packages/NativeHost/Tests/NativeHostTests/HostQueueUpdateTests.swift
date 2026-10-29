import ACP
import NativeHostClient
import NativeHostProtocol
import Testing

@testable import NativeHost

@Suite("Queue update ownership", .serialized, .timeLimit(.minutes(1)))
struct HostQueueUpdateTests {
    @Test("An item removed or drained after the client snapshot cannot acknowledge an edit", arguments: [false, true])
    func missingAfterSnapshot(drained: Bool) async throws {
        let harness = try HostHarness()
        defer { harness.cleanup() }
        try harness.start()
        let recorder = try await harness.connect()
        let session = try await recorder.client.newSession(
            NewSessionParams(agentID: "fake", cwd: harness.root.path(percentEncoded: false), attach: true))
        _ = try await recorder.client.prompt(PromptParams(sessionID: session.id, text: "slow 5"))
        let original = PromptParams(sessionID: session.id, text: "original comment packet", behavior: .queue)
        #expect(try await recorder.client.prompt(original) == .queued)
        let snapshot = try #require(try await recorder.client.sessions().first { $0.id == session.id })
        #expect(snapshot.queue.contains { $0.id == original.requestID })
        if drained {
            try await recorder.wait("both turns") { await $0.turnsEnded(session.id).count == 2 }
        } else {
            try await recorder.client.removeQueued(QueueItemParams(sessionID: session.id, itemID: original.requestID))
        }
        await #expect(throws: RPCError.self) {
            try await recorder.client.updateQueued(
                QueueItemParams(sessionID: session.id, itemID: original.requestID, text: "edited comment packet"))
        }
        #expect(try await recorder.client.sessions().first { $0.id == session.id }?.queue.isEmpty == true)
        #expect(await !recorder.mirror(session.id).userMessages.contains("edited comment packet"))
        if drained { #expect(await recorder.mirror(session.id).userMessages.contains("original comment packet")) }
        await recorder.stop()
    }

    @HostActor
    @Test("An in-flight steer cannot acknowledge an edit of its earlier queue snapshot")
    func inFlightSteerCannotAcknowledgeEdit() async throws {
        let rig = try HostStopCommandRig()
        defer { rig.cleanup() }
        let recorder = try await rig.connect()
        let summary = try await recorder.client.newSession(
            NewSessionParams(agentID: "fake", cwd: rig.harness.root.path, attach: true))
        let session = try #require(rig.core.sessions[summary.id])
        let original = OutgoingPrompt(text: "original comment packet")
        session.queue = [StoredQueueItem(prompt: original, isSteering: true)]
        try rig.core.store.setQueue(session.queue, for: session.id)
        await #expect(throws: RPCError.self) {
            try await recorder.client.updateQueued(
                QueueItemParams(sessionID: session.id, itemID: original.id, text: "edited comment packet"))
        }
        #expect(session.queue.map(\.prompt.text) == ["original comment packet"])
        await recorder.stop()
    }

}
