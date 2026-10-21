import ACP
import Foundation
import NativeHostClient
import NativeHostProtocol
import Testing

/// Sessions the host unloads while idle (`idleUnloadTimeout`): closed in the agent, kept in the
/// host with their transcript, and resumed without a replay when they're used again; the agent's
/// process ends once nothing is loaded. Nothing under way is ever cut off.
@Suite("Host idle unloading, end to end", .serialized, .timeLimit(.minutes(1)))
struct HostIdleUnloadTests {
    /// The fake agent, unloading sessions idle for a second.
    private func connect(_ harness: HostHarness) async throws -> Recorder {
        try harness.start()
        let recorder = try await harness.connect()
        var spec = harness.agentSpec
        spec.idleUnloadTimeout = 1
        try await recorder.client.syncAgents([spec])
        return recorder
    }

    private func resets(_ session: HostSessionID, in recorder: Recorder) async -> Int {
        await recorder.payloads(session).count { if case .reset = $0 { true } else { false } }
    }

    private func userMessages(_ session: HostSessionID, in recorder: Recorder) async -> [String] {
        await recorder.mirror(session).state.items.compactMap { item in
            if case .message(let message) = item, message.role == .user { message.text } else { nil }
        }
    }

    @Test("An idle session unloads, its agent stops, and the next message resumes it as it was")
    func unloadsAndResumesQuietly() async throws {
        let harness = try HostHarness()
        let recorder = try await connect(harness)
        let session = try await recorder.client.newSession(NewSessionParams(agentID: "fake", cwd: "/tmp", attach: true))
        try await recorder.client.setConfigOption(
            SetConfigOptionParams(sessionID: session.id, configID: "model", value: "beta"))
        try await recorder.client.setConfigOption(
            SetConfigOptionParams(sessionID: session.id, configID: "effort", value: "high"))
        _ = try await recorder.client.prompt(PromptParams(sessionID: session.id, text: "hello"))
        try await recorder.wait("the turn") { await $0.turnsEnded(session.id) == ["end_turn"] }
        let pid = try #require(await recorder.agents["fake"]?.processID)

        try await recorder.wait("the agent to stop", timeout: .seconds(15)) {
            await $0.agents["fake"]?.state == .stopped
        }
        #expect(kill(pid, 0) != 0)

        // Reading the retained transcript must not start the adapter or replay it again.
        try await recorder.client.detach(session.id)
        let summary = try await recorder.client.attach(session.id)
        #expect(summary.phase == .idle)
        #expect(await recorder.agents["fake"]?.state == .stopped)
        let resetCount = await resets(session.id, in: recorder)

        _ = try await recorder.client.prompt(PromptParams(sessionID: session.id, text: "config?"))
        try await recorder.wait("the next turn") { await $0.turnsEnded(session.id).count == 2 }
        #expect(await recorder.agentText(session.id).contains("model=beta effort=high"))
        #expect(await userMessages(session.id, in: recorder) == ["hello", "config?"])
        // Reattaching replays the retained log once; sending never resets it.
        #expect(await resets(session.id, in: recorder) == resetCount)
        #expect(harness.received.contains { $0.hasPrefix("resume\t") })
        let loads = try? String(contentsOf: harness.agentStore.appending(path: "loads.log"), encoding: .utf8)
        #expect(loads == nil)
        await recorder.stop()
    }

    @Test("A running turn or waiting user input keeps the session loaded", arguments: ["permission", "question"])
    func keepsWhatIsUnderWay(waitingFor: String) async throws {
        let harness = try HostHarness()
        let recorder = try await connect(harness)
        let working = try await recorder.client.newSession(NewSessionParams(agentID: "fake", cwd: "/tmp", attach: true))
        let asking = try await recorder.client.newSession(NewSessionParams(agentID: "fake", cwd: "/tmp", attach: true))
        _ = try await recorder.client.prompt(PromptParams(sessionID: working.id, text: "slow 12"))
        _ = try await recorder.client.prompt(PromptParams(sessionID: asking.id, text: waitingFor))
        try await recorder.wait("the approval") { await $0.summaries[asking.id]?.needsApproval == true }
        try await Task.sleep(for: .seconds(3))
        #expect(await recorder.agents["fake"]?.state != .stopped)
        #expect(!harness.received.contains { $0.hasPrefix("close\t") })

        try await recorder.wait("the slow turn") { await $0.turnsEnded(working.id) == ["end_turn"] }
        let closed = try #require(working.agentSessionID?.rawValue)
        // The other session still waits on the user, so this one goes alone.
        try await recorder.wait("the finished session to unload", timeout: .seconds(10)) { _ in
            harness.received.contains("close\t\(closed)")
        }
        #expect(await recorder.agents["fake"]?.state == .ready)
        #expect(await recorder.summaries[asking.id]?.needsApproval == true)
        await recorder.stop()
    }

    @Test("A session unloaded before its first turn starts afresh, showing the message once")
    func unsavedSessionStartsAfresh() async throws {
        let harness = try HostHarness()
        let recorder = try await connect(harness)
        let session = try await recorder.client.newSession(NewSessionParams(agentID: "fake", cwd: "/tmp", attach: true))
        try await recorder.wait("the agent to stop", timeout: .seconds(15)) {
            await $0.agents["fake"]?.state == .stopped
        }
        _ = try await recorder.client.prompt(PromptParams(sessionID: session.id, text: "hello"))
        try await recorder.wait("the turn") { await $0.turnsEnded(session.id) == ["end_turn"] }
        #expect(await recorder.agentText(session.id).contains("echo: hello"))
        #expect(await userMessages(session.id, in: recorder) == ["hello"])
        #expect(await resets(session.id, in: recorder) == 1)
        await recorder.stop()
    }
}
