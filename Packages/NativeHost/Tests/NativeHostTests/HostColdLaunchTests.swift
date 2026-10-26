import ACP
import Foundation
import NativeHostClient
import NativeHostProtocol
import Testing

@Suite("Cold-launch history readiness", .serialized, .timeLimit(.minutes(1)))
struct HostColdLaunchTests {
    @Test("A restored task reports loading before its history starts streaming", arguments: [false, true])
    func restoredOpenReportsLoading(attach: Bool) async throws {
        let harness = try HostHarness()
        defer { harness.cleanup() }
        try harness.start()
        let first = try await harness.connect()
        let original = try await first.client.newSession(
            NewSessionParams(agentID: "fake", cwd: harness.root.path(percentEncoded: false), attach: true))
        _ = try await first.client.prompt(
            PromptParams(sessionID: original.id, text: "```swift\nlet restored = true\n```"))
        try await first.wait("the completed code task") { await $0.turnsEnded(original.id) == ["end_turn"] }
        await first.stop()
        harness.kill()

        try harness.start()
        let second = try await harness.connect()
        let agentSession = try #require(original.agentSessionID)
        let opened =
            if attach {
                try await second.client.attach(original.id)
            } else {
                try await second.client.openSession(
                    OpenSessionParams(
                        agentID: "fake", agentSessionID: agentSession, cwd: original.cwd, attach: true))
            }
        #expect(opened.id == original.id)
        // The restored host record starts idle with an empty transcript. Clients must not mistake
        // that placeholder for a completed replay and fall back to a sample or an older task.
        #expect(opened.phase == .loading)
        try await second.wait("the restored code") { await $0.agentText(opened.id).contains("let restored = true") }
        try await second.wait("history completion") { await $0.summaries[opened.id]?.phase == .idle }
        #expect(await !second.mirror(opened.id).isLoading)
        #expect(harness.received.filter { $0.hasPrefix("prompt\t") }.count == 1)
        await second.stop()
    }
}
