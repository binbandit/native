import ACP
import Foundation
import NativeHostClient
import NativeHostProtocol
import Testing

@testable import NativeHost

@Suite("Host config ordering, end to end", .serialized, .timeLimit(.minutes(1)))
struct HostConfigOrderingTests {
    @Test("Two clients changing model and effort keep the later effort choice")
    func modelThenEffortAcrossClients() async throws {
        let harness = try HostHarness()
        defer { harness.cleanup() }
        harness.agentEnvironment["FAKE_AGENT_DELAY_MODEL"] = "1"
        try harness.start()
        let first = try await harness.connect()
        let second = try await harness.connect()
        let session = try await first.client.newSession(
            NewSessionParams(agentID: "fake", cwd: harness.root.path, attach: true))

        async let model: Void = first.client.setConfigOption(
            SetConfigOptionParams(sessionID: session.id, configID: "model", value: "beta"))
        try await first.wait("the model change to start") { _ in
            harness.received.contains("config-pending\tmodel=beta")
        }
        async let effort: Void = second.client.setConfigOption(
            SetConfigOptionParams(sessionID: session.id, configID: "effort", value: "high"))
        try await model
        try await effort
        #expect(try await first.client.sessions().first { $0.id == session.id }?.isHoldingRestart == false)

        _ = try await first.client.prompt(PromptParams(sessionID: session.id, text: "config?"))
        try await first.wait("the agent to report its settings") { await $0.turnsEnded(session.id).count == 1 }
        #expect(await first.agentText(session.id) == "config: mode=default model=beta effort=high")
        #expect(harness.received.filter { $0.hasPrefix("config\t") } == ["config\tmodel=beta", "config\teffort=high"])
        let saved = try HostStore(url: harness.location.databaseURL).sessions().first { $0.id == session.id }
        #expect(saved?.configChoices["model"] == "beta")
        #expect(saved?.configChoices["effort"] == "high")
        await first.stop()
        await second.stop()
    }

    @Test("A rejected model change does not prevent the next client's effort change")
    func rejectedChangeReleasesQueue() async throws {
        let harness = try HostHarness()
        defer { harness.cleanup() }
        harness.agentEnvironment["FAKE_AGENT_DELAY_MODEL"] = "1"
        harness.agentEnvironment["FAKE_AGENT_REJECT_MODEL"] = "1"
        try harness.start()
        let first = try await harness.connect()
        let second = try await harness.connect()
        let session = try await first.client.newSession(
            NewSessionParams(agentID: "fake", cwd: harness.root.path, attach: true))
        let model = Task {
            try await first.client.setConfigOption(
                SetConfigOptionParams(sessionID: session.id, configID: "model", value: "beta"))
        }
        try await first.wait("the model change to start") { _ in
            harness.received.contains("config-pending\tmodel=beta")
        }
        async let effort: Void = second.client.setConfigOption(
            SetConfigOptionParams(sessionID: session.id, configID: "effort", value: "high"))
        await #expect(throws: RPCError.self) { try await model.value }
        try await effort
        _ = try await first.client.prompt(PromptParams(sessionID: session.id, text: "config?"))
        try await first.wait("the agent to report its settings") { await $0.turnsEnded(session.id).count == 1 }
        #expect(await first.agentText(session.id) == "config: mode=default model=alpha effort=high")
        await first.stop()
        await second.stop()
    }

    @Test("Another session can change settings while the first session waits")
    func otherSessionsKeepWorking() async throws {
        let harness = try HostHarness()
        defer { harness.cleanup() }
        let gate = harness.root.appending(path: "config-gate")
        harness.agentEnvironment["FAKE_AGENT_CONFIG_GATE"] = gate.path
        try harness.start()
        let recorder = try await harness.connect()
        let first = try await recorder.client.newSession(NewSessionParams(agentID: "fake", cwd: harness.root.path))
        let second = try await recorder.client.newSession(NewSessionParams(agentID: "fake", cwd: harness.root.path))
        async let model: Void = recorder.client.setConfigOption(
            SetConfigOptionParams(sessionID: first.id, configID: "model", value: "beta"))
        try await recorder.wait("the first session's model change") { _ in
            harness.received.contains("config-pending\tmodel=beta")
        }
        async let effort: Void = recorder.client.setConfigOption(
            SetConfigOptionParams(sessionID: second.id, configID: "effort", value: "high"))
        try await recorder.wait("the other session's effort change", timeout: .seconds(3)) { _ in
            harness.received.contains("config\teffort=high")
        }
        try Data().write(to: gate)
        try await model
        try await effort
        await recorder.stop()
    }

    @Test("An idle update acknowledges settings before restarting", arguments: [false, true])
    func settingsReplyBeforeRestart(reject: Bool) async throws {
        let harness = try HostHarness()
        defer { harness.cleanup() }
        let gate = harness.root.appending(path: "config-gate")
        harness.agentEnvironment["FAKE_AGENT_CONFIG_GATE"] = gate.path
        if reject { harness.agentEnvironment["FAKE_AGENT_REJECT_MODEL"] = "1" }
        try harness.start()
        let recorder = try await harness.connect()
        let session = try await recorder.client.newSession(
            NewSessionParams(agentID: "fake", cwd: harness.root.path))
        let model = Task {
            try await recorder.client.setConfigOption(
                SetConfigOptionParams(sessionID: session.id, configID: "model", value: "beta"))
        }
        try await recorder.wait("the model change to start") { _ in
            harness.received.contains("config-pending\tmodel=beta")
        }
        try await recorder.client.shutdownHost(stopAgents: false)
        #expect(try await harness.waitForExit(timeout: .milliseconds(100)) == nil)
        try Data().write(to: gate)
        if reject {
            await #expect(throws: RPCError.self) { try await model.value }
        } else {
            try await model.value
        }
        #expect(try await harness.waitForExit() == 75)
        await recorder.stop()
    }

    @Test("Pending settings cannot outlive a restart or closed task", arguments: ["restart", "close"])
    @HostActor func replacedSessionRejectsPendingChanges(_ action: String) async throws {
        let rig = try HostStopCommandRig()
        defer { rig.cleanup() }
        let gate = rig.harness.root.appending(path: "config-gate")
        rig.harness.agentEnvironment["FAKE_AGENT_CONFIG_GATE"] = gate.path
        let first = try await rig.connect()
        let second = try await rig.connect()
        let summary = try await first.client.newSession(
            NewSessionParams(agentID: "fake", cwd: rig.harness.root.path))
        let session = try #require(rig.core.sessions[summary.id])
        let model = Task {
            try await first.client.setConfigOption(
                SetConfigOptionParams(sessionID: session.id, configID: "model", value: "beta"))
        }
        try await first.wait("the model change") { _ in rig.harness.received.contains("config-pending\tmodel=beta") }
        let initialChange = try #require(session.configChange?.id)
        #expect(session.holdsRestart)
        let effort = Task {
            try await second.client.setConfigOption(
                SetConfigOptionParams(sessionID: session.id, configID: "effort", value: "high"))
        }
        try await first.wait("the second client's pending change") { _ in
            await session.configChange?.id != initialChange
        }
        if action == "restart" {
            _ = try await first.client.restartAgent("fake")
        } else {
            try await first.client.closeSession(session.id)
        }
        try Data().write(to: gate)
        await #expect(throws: RPCError.self) { try await model.value }
        await #expect(throws: RPCError.self) { try await effort.value }
        #expect(!rig.harness.received.contains("config\teffort=high"))
        #expect(session.configChange == nil)
        await first.stop()
        await second.stop()
    }
}
