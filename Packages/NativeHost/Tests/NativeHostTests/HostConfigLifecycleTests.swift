import ACP
import Foundation
import NativeHostClient
import NativeHostProtocol
import Testing

@testable import NativeHost

@Suite("Host config lifecycle, end to end", .serialized, .timeLimit(.minutes(1)))
struct HostConfigLifecycleTests {
    private func savedSession(_ harness: HostHarness) async throws -> (Recorder, HostSessionSummary) {
        try harness.start()
        let recorder = try await harness.connect()
        let session = try await recorder.client.newSession(
            NewSessionParams(agentID: "fake", cwd: harness.root.path(percentEncoded: false), attach: true))
        try await recorder.client.setConfigOption(
            SetConfigOptionParams(sessionID: session.id, configID: "model", value: "beta"))
        try await recorder.client.setConfigOption(
            SetConfigOptionParams(sessionID: session.id, configID: "effort", value: "high"))
        _ = try await recorder.client.prompt(PromptParams(sessionID: session.id, text: "config?"))
        try await recorder.wait("the saved turn") { await $0.turnsEnded(session.id) == ["end_turn"] }
        return (recorder, session)
    }

    private func checkConfig(_ recorder: Recorder, _ session: HostSessionID) async throws {
        _ = try await recorder.client.prompt(PromptParams(sessionID: session, text: "config?"))
        try await recorder.wait("the check") { await $0.turnsEnded(session).count == 1 }
        let options = await recorder.mirror(session).state.configOptions
        let values = Dictionary(
            uniqueKeysWithValues: options.compactMap { option -> (String, String)? in
                guard case .select(let value, _) = option.kind else { return nil }
                return (option.id, value)
            })
        #expect(values["model"] == "beta")
        #expect(values["effort"] == "high")
    }

    @Test("Closing and reopening a saved session keeps its settings across a host restart")
    func closedSessionKeepsConfig() async throws {
        let harness = try HostHarness()
        let (first, session) = try await savedSession(harness)
        let agentSessionID = try #require(session.agentSessionID)
        try await first.client.closeSession(session.id, closeInAgent: true)
        harness.kill()
        await first.stop()
        try harness.start()
        let second = try await harness.connect()
        let reopened = try await second.client.openSession(
            OpenSessionParams(
                agentID: "fake", agentSessionID: agentSessionID, cwd: session.cwd,
                configChoices: ["model": "alpha", "effort": "low"]))
        try await second.client.attach(reopened.id)
        try await checkConfig(second, reopened.id)
        await second.stop()
    }

    @Test("First adoption accepts local choices, but reopening an existing host session ignores stale client values")
    func adoptedSessionUsesFallbackOnlyOnce() async throws {
        let harness = try HostHarness()
        let (first, session) = try await savedSession(harness)
        let agentSessionID = try #require(session.agentSessionID)
        harness.kill()
        await first.stop()
        // History exists only in the agent, as for a session that previously ran inside the app.
        try HostStore(url: harness.location.databaseURL).deleteSession(session.id)
        try harness.start()
        let second = try await harness.connect()
        let adopted = try await second.client.openSession(
            OpenSessionParams(
                agentID: "fake", agentSessionID: agentSessionID, cwd: session.cwd,
                configChoices: ["model": "beta", "effort": "high"]))
        _ = try await second.client.restartAgent("fake")
        let reopened = try await second.client.openSession(
            OpenSessionParams(
                agentID: "fake", agentSessionID: agentSessionID, cwd: session.cwd,
                configChoices: ["model": "alpha", "effort": "low"]))
        #expect(reopened.id == adopted.id)
        try await second.client.attach(reopened.id)
        try await checkConfig(second, reopened.id)
        await second.stop()
    }

    @Test("An agent disconnecting during restoration does not replace the durable choices")
    func disconnectedRestoreKeepsConfig() async throws {
        let harness = try HostHarness()
        harness.agentEnvironment["FAKE_AGENT_CRASH_ON_RESTORE"] = "1"
        let (first, session) = try await savedSession(harness)
        let agentSessionID = try #require(session.agentSessionID)
        _ = try await first.client.restartAgent("fake")
        do {
            _ = try await first.client.openSession(
                OpenSessionParams(agentID: "fake", agentSessionID: agentSessionID, cwd: session.cwd))
            Issue.record("A disconnected restoration must fail the load")
        } catch {}
        #expect(harness.received.contains("restore-crash\tmodel"))
        let stored = try HostStore(url: harness.location.databaseURL).sessions().first { $0.id == session.id }
        #expect(stored?.configChoices["model"] == "beta")
        #expect(stored?.configChoices["effort"] == "high")
        harness.kill()
        await first.stop()
        try harness.start()
        let second = try await harness.connect()
        _ = try await second.client.openSession(
            OpenSessionParams(agentID: "fake", agentSessionID: agentSessionID, cwd: session.cwd))
        try await second.client.attach(session.id)
        try await checkConfig(second, session.id)
        await second.stop()
    }
}
