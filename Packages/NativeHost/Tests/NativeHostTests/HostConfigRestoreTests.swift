import ACP
import Foundation
import NativeHostClient
import NativeHostProtocol
import Testing

/// The settings a user chose for a session (model, effort, mode) as they come through a host that
/// dies mid-turn: the new host reloads the session, sets them back in order and checks the agent
/// took them, before the interrupted turn carries on.
@Suite("Host config restore, end to end", .serialized, .timeLimit(.minutes(1)))
struct HostConfigRestoreTests {
    private func started(_ harness: HostHarness) async throws -> (Recorder, HostSessionID) {
        try harness.start()
        let recorder = try await harness.connect()
        let summary = try await recorder.client.newSession(
            NewSessionParams(agentID: "fake", cwd: harness.root.path(percentEncoded: false), attach: true))
        return (recorder, summary.id)
    }

    private func current(_ id: String, in mirror: SessionMirror) -> String? {
        guard case .select(let value, _)? = mirror.state.configOptions.first(where: { $0.id == id })?.kind else {
            return nil
        }
        return value
    }

    @Test("Killing the host mid-turn keeps the chosen model and effort")
    func hostKilledMidTurn() async throws {
        let harness = try HostHarness()
        let (first, session) = try await started(harness)
        try await first.client.setConfigOption(
            SetConfigOptionParams(sessionID: session, configID: "model", value: "beta"))
        try await first.client.setConfigOption(
            SetConfigOptionParams(sessionID: session, configID: "effort", value: "high"))
        _ = try await first.client.prompt(PromptParams(sessionID: session, text: "slow 30"))
        try await first.wait("the turn to get going") { await $0.agentText(session).contains("tick 2") }
        harness.kill()
        await first.stop()

        try harness.start()
        let second = try await harness.connect()
        try await second.client.attach(session)
        try await second.wait("the resumed turn to end", timeout: .seconds(30)) {
            await $0.turnsEnded(session) == ["end_turn"]
        }
        #expect(current("model", in: await second.mirror(session)) == "beta")
        #expect(current("effort", in: await second.mirror(session)) == "high")
        _ = try await second.client.prompt(PromptParams(sessionID: session, text: "config?"))
        try await second.wait("the check") { await $0.turnsEnded(session).count == 2 }
        #expect(await second.agentText(session).contains("model=beta effort=high"))
        await second.stop()
    }
}
