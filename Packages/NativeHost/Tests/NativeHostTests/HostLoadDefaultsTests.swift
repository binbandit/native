import ACP
import Foundation
import NativeHostClient
import NativeHostProtocol
import Testing

@testable import NativeHost

@Suite("Loaded session defaults", .serialized, .timeLimit(.minutes(1)))
struct HostLoadDefaultsTests {
    private func history(_ harness: HostHarness) async throws -> HostSessionSummary {
        try harness.start()
        let recorder = try await harness.connect()
        let session = try await recorder.client.newSession(
            NewSessionParams(agentID: "fake", cwd: harness.root.path(percentEncoded: false), attach: true))
        _ = try await recorder.client.prompt(PromptParams(sessionID: session.id, text: "config?"))
        try await recorder.wait("history to be saved") { await $0.turnsEnded(session.id) == ["end_turn"] }
        harness.kill()
        await recorder.stop()
        return session
    }

    private func values(_ recorder: Recorder, _ id: HostSessionID) async -> [String: String] {
        await HostCore.configValues(recorder.mirror(id).state.configOptions)
    }

    @Test("Settings fill only missing choices, for both adopted and existing host records", arguments: [false, true])
    func fillsMissingChoices(existing: Bool) async throws {
        let harness = try HostHarness()
        harness.agentEnvironment["FAKE_AGENT_RELOAD_UPDATES"] = "1"
        let session = try await history(harness)
        let agentSessionID = try #require(session.agentSessionID)
        let store = try HostStore(url: harness.location.databaseURL)
        if existing {
            var record = try #require(store.sessions().first { $0.id == session.id })
            record.configChoices = ["mode": "plan"]
            try store.updateSession(record)
        } else {
            try store.deleteSession(session.id)
        }
        try harness.start()
        let recorder = try await harness.connect()
        let opened = try await recorder.client.openSession(
            OpenSessionParams(
                agentID: "fake", agentSessionID: agentSessionID, cwd: session.cwd,
                configDefaults: ["model": "beta", "thought_level": "high"]))
        try await recorder.client.attach(opened.id)
        #expect(await values(recorder, opened.id)["model"] == "beta")
        #expect(await values(recorder, opened.id)["effort"] == "high")
        #expect(await values(recorder, opened.id)["mode"] == (existing ? "plan" : "default"))
        let saved = try #require(store.sessions().first { $0.id == opened.id })
        #expect(saved.configChoices["model"] == "beta")
        #expect(saved.configChoices["effort"] == "high")
        #expect(
            harness.received.filter { $0.hasPrefix("config\tmodel=") || $0.hasPrefix("config\teffort=") } == [
                "config\tmodel=beta", "config\teffort=high",
            ])

        // Settings changing later cannot replace what the first open saved, even after closing
        // the host record and restarting the host itself.
        try await recorder.client.closeSession(opened.id, closeInAgent: true)
        harness.kill()
        await recorder.stop()
        try harness.start()
        let reopened = try await harness.connect()
        let second = try await reopened.client.openSession(
            OpenSessionParams(
                agentID: "fake", agentSessionID: agentSessionID, cwd: session.cwd,
                configDefaults: ["model": "alpha", "thought_level": "low"]))
        try await reopened.client.attach(second.id)
        #expect(await values(reopened, second.id)["model"] == "beta")
        #expect(await values(reopened, second.id)["effort"] == "high")
        await reopened.stop()
    }

    @Test("A saved model wins independently of an unset effort")
    func savedModelWins() async throws {
        let harness = try HostHarness()
        let session = try await history(harness)
        let store = try HostStore(url: harness.location.databaseURL)
        var record = try #require(store.sessions().first { $0.id == session.id })
        record.configChoices = ["model": "alpha"]
        try store.updateSession(record)
        try harness.start()
        let recorder = try await harness.connect()
        _ = try await recorder.client.openSession(
            OpenSessionParams(
                agentID: "fake", agentSessionID: try #require(session.agentSessionID), cwd: session.cwd,
                configDefaults: ["model": "beta", "thought_level": "low"]))
        try await recorder.client.attach(session.id)
        #expect(await values(recorder, session.id)["model"] == "alpha")
        #expect(await values(recorder, session.id)["effort"] == "low")
        #expect(!harness.received.contains("config\tmodel=beta"))
        await recorder.stop()
    }

    @Test("Without usable Settings defaults the session keeps what the agent reports", arguments: [false, true])
    func keepsReportedValues(unavailable: Bool) async throws {
        let harness = try HostHarness()
        let session = try await history(harness)
        try HostStore(url: harness.location.databaseURL).deleteSession(session.id)
        try harness.start()
        let recorder = try await harness.connect()
        let opened = try await recorder.client.openSession(
            OpenSessionParams(
                agentID: "fake", agentSessionID: try #require(session.agentSessionID), cwd: session.cwd,
                configDefaults: unavailable ? ["model": "removed", "thought_level": "removed"] : nil))
        try await recorder.client.attach(opened.id)
        #expect(await values(recorder, opened.id)["model"] == "alpha")
        #expect(await values(recorder, opened.id)["effort"] == "medium")
        #expect(!harness.received.contains { $0.hasPrefix("config\t") })
        await recorder.stop()
    }
}
