import ACP
import Foundation
import NativeHostClient
import NativeHostProtocol
import Testing

@Suite(.serialized, .timeLimit(.minutes(1)))
struct ConfirmedSessionCloseTests {
    @Test(arguments: ["FAKE_AGENT_NO_CLOSE", "FAKE_AGENT_REJECT_CLOSE"])
    func refusalKeepsTheHostRecordAndAllowsRetry(_ setting: String) async throws {
        let harness = try HostHarness()
        defer { harness.cleanup() }
        harness.agentEnvironment[setting] = "1"
        try harness.start()
        let recorder = try await harness.connect()
        let summary = try await recorder.client.newSession(
            NewSessionParams(agentID: "fake", cwd: harness.root.path, attach: true))
        let file = harness.root.appendingPathComponent("draft.txt")
        try Data("Keep my work".utf8).write(to: file)
        var refused = false
        do {
            try await recorder.client.closeSessionConfirmed(summary.id)
            try FileManager.default.removeItem(at: file)
        } catch {
            refused = true
        }
        #expect(FileManager.default.fileExists(atPath: file.path))
        #expect(try await recorder.client.sessions().contains { $0.id == summary.id })
        try #require(refused)
        if setting == "FAKE_AGENT_REJECT_CLOSE" {
            try Data().write(to: harness.agentStore.appendingPathComponent("allow-close"))
        } else {
            _ = try await recorder.client.stopAgent("fake")
            try await Task.sleep(for: .seconds(3))
        }
        try await recorder.client.closeSessionConfirmed(summary.id)
        #expect(try await !recorder.client.sessions().contains { $0.id == summary.id })
        #expect(FileManager.default.fileExists(atPath: file.path))
        await recorder.stop()
    }
    @Test func cleanupAfterCancellingATurnWaitsForItsOwnedProcesses() async throws {
        let harness = try HostHarness()
        defer { harness.cleanup() }
        harness.agentEnvironment["FAKE_AGENT_NO_CLOSE"] = "1"
        try harness.start()
        let recorder = try await harness.connect()
        let summary = try await recorder.client.newSession(
            NewSessionParams(agentID: "fake", cwd: harness.root.path, attach: true))
        _ = try await recorder.client.prompt(PromptParams(sessionID: summary.id, text: "slow 100"))
        await #expect(throws: (any Error).self) { try await recorder.client.closeSessionConfirmed(summary.id) }
        try await recorder.client.cancel(summary.id)
        try await recorder.wait("the owned processes to stop") {
            let agent = await $0.agents["fake"]
            let task = await $0.summaries[summary.id]
            return agent?.state == .stopped && task?.isStopping == false
        }
        try await recorder.client.closeSessionConfirmed(summary.id)
        #expect(try await !recorder.client.sessions().contains { $0.id == summary.id })
        await recorder.stop()
    }

}
