// These tools require the host's Network and CryptoKit MCP transport.
#if canImport(Network) && canImport(CryptoKit)
import ACP
import Foundation
import NativeHostClient
import NativeHostProtocol
import Testing

@Suite(.serialized, .timeLimit(.minutes(2)))
struct HostDelegationTests {
    @Test func exactSelectionsPrecedeFirstPrompt() async throws {
        let harness = try HostHarness()
        defer { harness.cleanup() }
        try harness.start()
        let recorder = try await harness.connect()
        let parent = try await recorder.client.newSession(NewSessionParams(agentID: "fake", cwd: harness.root.path))
        let checkout = harness.root.appending(path: "checkout")
        try FileManager.default.createDirectory(at: checkout, withIntermediateDirectories: true)
        let result = try await recorder.client.callTool(
            CallToolParams(
                sessionID: parent.id, tool: "start_task",
                arguments: .object([
                    "agent": .string("fake"), "prompt": .string("check settings"), "model": .string("beta"),
                    "effort": .string("low"), "permissions": .string("ask-first"), "checkout": .string(checkout.path),
                ])))
        #expect(!result.isError, "\(result.text)")
        let task = try #require(try await recorder.client.tasks().first)
        #expect(task.cwd == checkout.resolvingSymlinksInPath().path)
        let child = try #require(task.sessionID)
        try await recorder.client.attach(child)
        try await recorder.wait("child result") { await $0.turnsEnded(child) == ["end_turn"] }
        let options = await recorder.mirror(child).state.configOptions
        for (id, value) in [("model", "beta"), ("effort", "low"), ("mode", "default")] {
            let option = try #require(options.first { $0.id == id })
            guard case .select(let current, _) = option.kind else { Issue.record("Missing select"); continue }
            #expect(current == value)
        }
        let received = harness.received
        let prompt = try #require(received.firstIndex { $0.hasPrefix("prompt\t") })
        for config in ["config\tmodel=beta", "config\teffort=low", "config\tmode=default"] {
            #expect(try #require(received.firstIndex(of: config)) < prompt)
        }
        await recorder.stop()
    }

    @Test func refusalsNeverPromptACandidate() async throws {
        let harness = try HostHarness()
        defer { harness.cleanup() }
        try harness.start()
        let recorder = try await harness.connect()
        let parent = try await recorder.client.newSession(NewSessionParams(agentID: "fake", cwd: harness.root.path))
        for selection in [
            "model": "unavailable", "effort": "unavailable", "permissions": "full-access",
            "checkout": "/missing-checkout",
        ] {
            let result = try await recorder.client.callTool(
                CallToolParams(
                    sessionID: parent.id, tool: "start_task",
                    arguments: .object([
                        "agent": .string("fake"), "prompt": .string("must not run"),
                        selection.key: .string(selection.value),
                    ])))
            #expect(result.isError)
        }
        #expect(try await recorder.client.tasks().isEmpty)
        #expect(!harness.received.contains { $0.hasPrefix("prompt\t") })
        let discovery = try await recorder.client.callTool(
            CallToolParams(sessionID: parent.id, tool: "list_agents", arguments: .object(["limit": .number(1)])))
        #expect(discovery.text.contains("last observed"))
        await recorder.stop()
    }
}
#endif
