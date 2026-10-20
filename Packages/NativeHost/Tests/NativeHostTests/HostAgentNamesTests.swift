import ACP
import Foundation
import NativeHostClient
import NativeHostProtocol
import Testing

/// Sessions named in their agent ahead of their turns (`AgentSpec.renameCommand`), against the fake
/// agent answering `/rename` as codex-acp 2.2.2 does: without a model, a null usage, then the title.
@Suite("Host naming sessions in their agent, end to end", .serialized, .timeLimit(.minutes(1)))
struct HostAgentNamesTests {
    /// The fake agent with codex-acp's rename command, and titles written by clients, as the app does.
    private func connect(_ harness: HostHarness) async throws -> Recorder {
        try harness.start()
        let recorder = try await harness.connect()
        var spec = harness.agentSpec
        spec.renameCommand = "/rename"
        try await recorder.client.syncAgents([spec])
        try await recorder.client.configureTitles(ConfigureTitlesParams(provider: .client))
        return recorder
    }

    private func send(_ text: String, to session: HostSessionID, in recorder: Recorder) async throws {
        let ended = await recorder.turnsEnded(session).count
        _ = try await recorder.client.prompt(PromptParams(sessionID: session, text: text))
        try await recorder.wait("the turn") { await $0.turnsEnded(session).count == ended + 1 }
    }

    private func shownMessages(_ session: HostSessionID, in recorder: Recorder) async -> [String] {
        await recorder.mirror(session).state.items.compactMap { item in
            if case .message(let message) = item { message.text } else { nil }
        }
    }

    @Test("A new session is named before its first message, and its title follows Native's from then on")
    func namesAheadOfTurns() async throws {
        let harness = try HostHarness()
        let recorder = try await connect(harness)
        let session = try await recorder.client.newSession(NewSessionParams(agentID: "fake", cwd: "/tmp", attach: true))

        try await send("fix the failing test in greet.py", to: session.id, in: recorder)
        #expect(
            harness.received == [
                "rename\tFix the failing test in greet.py", "prompt\tfix the failing test in greet.py",
            ])
        #expect(await recorder.mirror(session.id).state.title == "Fix the failing test in greet.py")

        try await recorder.client.setSessionTitle(
            SetSessionTitleParams(sessionID: session.id, title: "Greet test fix", source: .generated))
        try await send("again", to: session.id, in: recorder)
        try await send("and again", to: session.id, in: recorder)
        #expect(harness.received.filter { $0.hasPrefix("rename\t") }.count == 2)
        #expect(harness.received.suffix(3) == ["rename\tGreet test fix", "prompt\tagain", "prompt\tand again"])
        // The renames never show: the transcript is the conversation alone.
        #expect(
            await shownMessages(session.id, in: recorder) == [
                "fix the failing test in greet.py", "echo: fix the failing test in greet.py", "again", "echo: again",
                "and again", "echo: and again",
            ])
        await recorder.stop()
    }

    @Test("An agent that answers the rename with a model's turn isn't asked again, and nothing of it shows")
    func stopsWhenAModelAnswers() async throws {
        let harness = try HostHarness()
        harness.agentEnvironment["FAKE_AGENT_RENAME_ASKS_MODEL"] = "1"
        let recorder = try await connect(harness)
        let first = try await recorder.client.newSession(NewSessionParams(agentID: "fake", cwd: "/tmp", attach: true))
        try await send("hello there", to: first.id, in: recorder)
        #expect(await shownMessages(first.id, in: recorder) == ["hello there", "echo: hello there"])

        let second = try await recorder.client.newSession(NewSessionParams(agentID: "fake", cwd: "/tmp", attach: true))
        try await send("good morning", to: second.id, in: recorder)
        #expect(harness.received == ["prompt\t/rename Hello there", "prompt\thello there", "prompt\tgood morning"])
        await recorder.stop()
    }
}
