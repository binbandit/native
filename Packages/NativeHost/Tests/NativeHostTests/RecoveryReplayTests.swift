import ACP
import Foundation
import NativeHostClient
import NativeHostProtocol
import Testing

@testable import NativeHost

@Suite("Recovery history, end to end", .serialized, .timeLimit(.minutes(1)))
struct RecoveryReplayTests {
    @Test("Reopening a recovered session keeps Native's prompt out of the user's messages")
    func reopenRecoveredSession() async throws {
        let harness = try HostHarness()
        try harness.start()
        let first = try await harness.connect()
        let summary = try await first.client.newSession(
            NewSessionParams(agentID: "fake", cwd: harness.root.path(percentEncoded: false)))
        let session = summary.id
        try await first.client.attach(session)
        let userPrompt = "crash-once recovery replay"
        _ = try await first.client.prompt(PromptParams(sessionID: session, text: userPrompt))
        try await first.wait("the recovered turn to finish") { await $0.turnsEnded(session) == ["end_turn"] }
        #expect(await first.agentText(session).contains("resumed"))
        await first.stop()
        harness.kill()

        // A new host has to load the agent's history, including the recovery prompt it persisted.
        try harness.start()
        let second = try await harness.connect()
        try await second.client.attach(session)
        try await second.wait("the agent's history to load") {
            await $0.payloads(session).contains { if case .loaded = $0 { true } else { false } }
        }
        let mirror = await second.mirror(session)
        let users = mirror.state.items.compactMap { item -> String? in
            if case .message(let message) = item, message.role == .user { message.text } else { nil }
        }
        #expect(users == [userPrompt])
        #expect(mirror.state.turns.count == 1)
        #expect(
            await second.notices(session).contains(
                "This turn was interrupted because the agent stopped unexpectedly. Native asked the agent to pick up where it left off."
            ))
        #expect(mirror.userMessages == [userPrompt, RecoveryPlanner.interruptionPrompt(cause: .agentStopped)])
        #expect(harness.received.filter { $0.hasPrefix("prompt\t") }.count == 2)
        await second.stop()
    }
}
