import ACP
import Foundation
import NativeHostClient
import NativeHostProtocol
import Testing

/// The settings a session runs with (model, effort, mode) as they come through a host that dies
/// mid-turn: the new host reloads the session, sets back what it ran with, model first, and checks
/// the agent took it, before the interrupted turn carries on.
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

    /// Kills the host in the middle of a turn and starts it again, as a crash and launchd would; the
    /// returned client follows the session once the interrupted turn has finished.
    private func killedMidTurn(
        _ harness: HostHarness, _ first: Recorder, _ session: HostSessionID
    ) async throws -> Recorder {
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
        return second
    }

    /// The config options clients were sent since the last reset, as `id=value` for model and effort.
    private func reportedSinceReset(_ recorder: Recorder, _ session: HostSessionID) async -> [String] {
        let payloads = await recorder.payloads(session)
        let start = payloads.lastIndex { if case .reset = $0 { true } else { false } } ?? payloads.startIndex
        return payloads[start...].compactMap { payload -> String? in
            guard case .update(let update) = payload, update["sessionUpdate"]?.stringValue == "config_option_update",
                case .array(let options)? = update["configOptions"]
            else { return nil }
            return options.compactMap { option -> String? in
                guard let id = option["id"]?.stringValue, id == "model" || id == "effort" else { return nil }
                return "\(id)=\(option["currentValue"]?.stringValue ?? "")"
            }.joined(separator: " ")
        }
    }

    @Test("Killing the host mid-turn keeps the chosen model and effort")
    func hostKilledMidTurn() async throws {
        let harness = try HostHarness()
        let (first, session) = try await started(harness)
        try await first.client.setConfigOption(
            SetConfigOptionParams(sessionID: session, configID: "model", value: "beta"))
        try await first.client.setConfigOption(
            SetConfigOptionParams(sessionID: session, configID: "effort", value: "high"))
        let second = try await killedMidTurn(harness, first, session)
        #expect(current("model", in: await second.mirror(session)) == "beta")
        #expect(current("effort", in: await second.mirror(session)) == "high")
        _ = try await second.client.prompt(PromptParams(sessionID: session, text: "config?"))
        try await second.wait("the check") { await $0.turnsEnded(session).count == 2 }
        #expect(await second.agentText(session).contains("model=beta effort=high"))
        await second.stop()
    }

    @Test(
        "Clients never see the agent's defaults while a reloaded session gets its settings back",
        arguments: [false, true])
    func noDefaultsOnReload(notifications: Bool) async throws {
        let harness = try HostHarness()
        if notifications { harness.agentEnvironment["FAKE_AGENT_RELOAD_UPDATES"] = "1" }
        let (first, session) = try await started(harness)
        try await first.client.setConfigOption(
            SetConfigOptionParams(sessionID: session, configID: "model", value: "beta"))
        try await first.client.setConfigOption(
            SetConfigOptionParams(sessionID: session, configID: "effort", value: "high"))
        let second = try await killedMidTurn(harness, first, session)
        // The reload reported alpha and medium; only where the settings ended up went out.
        #expect(await reportedSinceReset(second, session) == ["effort=high model=beta"])
        await second.stop()
    }

    @Test("A choice the agent refuses after the host restarts is said once, and the session carries on")
    func refusedAfterRestart() async throws {
        let harness = try HostHarness()
        harness.agentEnvironment["FAKE_AGENT_LOCKED_ON_RELOAD"] = "effort"
        let (first, session) = try await started(harness)
        try await first.client.setConfigOption(
            SetConfigOptionParams(sessionID: session, configID: "effort", value: "high"))
        let second = try await killedMidTurn(harness, first, session)
        #expect(harness.received.contains("locked\teffort=high"))
        #expect(
            await second.notices(session).contains(
                "Fake Agent didn't take back High for Effort, so this session uses Medium. Choose it again to retry."))
        #expect(current("effort", in: await second.mirror(session)) == "medium")
        // Said once: the next reload doesn't try again.
        _ = try await second.client.restartAgent("fake")
        _ = try await second.client.prompt(PromptParams(sessionID: session, text: "config?"))
        try await second.wait("the check") { await $0.turnsEnded(session).count == 2 }
        #expect(harness.received.filter { $0.hasPrefix("locked\t") }.count == 1)
        await second.stop()
    }

    @Test("An agent that answers but keeps its own value after a restart is caught too")
    func keptAfterRestart() async throws {
        let harness = try HostHarness()
        harness.agentEnvironment["FAKE_AGENT_LOCKED_ON_RELOAD"] = "model=keep"
        let (first, session) = try await started(harness)
        try await first.client.setConfigOption(
            SetConfigOptionParams(sessionID: session, configID: "model", value: "beta"))
        let second = try await killedMidTurn(harness, first, session)
        #expect(
            await second.notices(session).contains(
                "Fake Agent didn't take back Beta for Model, so this session uses Alpha. Choose it again to retry."))
        // A client setting it back itself (as the app does after a load) gets the same answer; what
        // the host remembers is what the agent took, so the next reload doesn't say it again.
        try await second.client.setConfigOption(
            SetConfigOptionParams(sessionID: session, configID: "model", value: "beta"))
        _ = try await second.client.restartAgent("fake")
        _ = try await second.client.prompt(PromptParams(sessionID: session, text: "config?"))
        try await second.wait("the check") { await $0.turnsEnded(session).count == 2 }
        #expect(await second.notices(session).filter { $0.contains("didn't take back") }.isEmpty)
        #expect(await second.agentText(session).contains("model=alpha"))
        await second.stop()
    }

    @Test("Settings nobody chose come back too, when the agent reopens the session on other defaults")
    func pinnedDefaultsComeBack() async throws {
        let harness = try HostHarness()
        // As codex-acp coming back on its built-in defaults: the session ran on Medium, never chosen.
        harness.agentEnvironment["FAKE_AGENT_RELOAD_DEFAULTS"] = "effort=low"
        let (first, session) = try await started(harness)
        let second = try await killedMidTurn(harness, first, session)
        #expect(harness.received.contains("config\teffort=medium"))
        #expect(await reportedSinceReset(second, session) == ["effort=medium model=alpha"])
        #expect(await second.notices(session).filter { $0.contains("didn't take back") }.isEmpty)
        _ = try await second.client.prompt(PromptParams(sessionID: session, text: "config?"))
        try await second.wait("the check") { await $0.turnsEnded(session).count == 2 }
        #expect(await second.agentText(session).contains("effort=medium"))
        await second.stop()
    }

    @Test("Settings or values removed on reload are explained", arguments: ["effort", "effort=high"])
    func unavailableAfterRestart(missing: String) async throws {
        let harness = try HostHarness()
        harness.agentEnvironment["FAKE_AGENT_RELOAD_MISSING"] = missing
        let (first, session) = try await started(harness)
        try await first.client.setConfigOption(
            SetConfigOptionParams(sessionID: session, configID: "effort", value: "high"))
        let second = try await killedMidTurn(harness, first, session)
        #expect(await second.notices(session).contains { $0.contains("no longer offers") && $0.contains("high") })
        #expect(!harness.received.contains("locked\teffort=high"))
        await second.stop()
    }

    @Test("A new session after a restart starts on the agent's defaults, not on what another session ran with")
    func newSessionAfterRestart() async throws {
        let harness = try HostHarness()
        harness.agentEnvironment["FAKE_AGENT_RELOAD_DEFAULTS"] = "effort=low"
        let (first, session) = try await started(harness)
        try await first.client.setConfigOption(
            SetConfigOptionParams(sessionID: session, configID: "effort", value: "high"))
        let second = try await killedMidTurn(harness, first, session)
        #expect(current("effort", in: await second.mirror(session)) == "high")
        let fresh = try await second.client.newSession(
            NewSessionParams(agentID: "fake", cwd: harness.root.path(percentEncoded: false), attach: true))
        // Neither the reloaded session's Low nor its chosen High.
        #expect(current("effort", in: await second.mirror(fresh.id)) == "medium")
        await second.stop()
    }

    @Test("A setting the agent changed itself isn't undone by a reload")
    func agentsOwnChangeStands() async throws {
        let harness = try HostHarness()
        let (recorder, session) = try await started(harness)
        try await recorder.client.setConfigOption(
            SetConfigOptionParams(sessionID: session, configID: "mode", value: "plan"))
        _ = try await recorder.client.prompt(PromptParams(sessionID: session, text: "leave-plan"))
        try await recorder.wait("the turn") { await $0.turnsEnded(session) == ["end_turn"] }
        _ = try await recorder.client.restartAgent("fake")
        _ = try await recorder.client.prompt(PromptParams(sessionID: session, text: "mode?"))
        try await recorder.wait("the check") { await $0.turnsEnded(session).count == 2 }
        #expect(await recorder.agentText(session).contains("mode: default"))
        #expect(harness.received.filter { $0 == "config\tmode=plan" }.count == 1)
        await recorder.stop()
    }
}
