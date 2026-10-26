import ACP
import NativeHostClient
import NativeHostProtocol
import Testing

@Suite("Agent startup failures", .serialized, .timeLimit(.minutes(1)))
struct HostAgentFailureTests {
    @Test(
        "A failed launch stays failed until a successful retry",
        arguments: [
            "printf 'startup diagnostic\\n' >&2; exit 7",
            "read request; printf '%s\\n' '{\"jsonrpc\":\"2.0\",\"id\":0,\"error\":{\"code\":-32603,\"message\":\"startup diagnostic\"}}'; cat >/dev/null",
        ])
    func failedStartup(command: String) async throws {
        let harness = try HostHarness()
        defer { harness.cleanup() }
        try harness.start()
        let recorder = try await harness.connect()
        let broken = AgentSpec(id: "fake", name: "Fake Agent", command: "/bin/sh", args: ["-c", command])
        try await recorder.client.syncAgents([broken])

        let started = try await recorder.client.startAgent("fake")
        #expect(started.state == .failed)
        #expect(started.problem?.contains("startup diagnostic") == true)
        #expect(started.problem?.contains("Choose Restart") == true)
        #expect(started.processID == nil)
        #expect(started.initialize == nil)
        #expect(try await recorder.client.agents().first?.state == .failed)
        #expect(await recorder.agents["fake"]?.state == .failed)

        let retried = try await recorder.client.restartAgent("fake")
        #expect(retried.state == .failed)
        #expect(retried.problem?.contains("startup diagnostic") == true)

        try await recorder.client.syncAgents([harness.agentSpec])
        let recovered = try await recorder.client.restartAgent("fake")
        #expect(recovered.state == .ready)
        #expect(recovered.problem == nil)
        #expect(recovered.processID != nil)
        #expect(recovered.initialize != nil)
        #expect(await recorder.agents["fake"]?.state == .ready)
        await recorder.stop()
    }
}
