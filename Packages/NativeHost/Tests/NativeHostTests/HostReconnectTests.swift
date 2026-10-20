import ACP
import Foundation
import NativeHostClient
import NativeHostProtocol
import Testing

/// The connection between a client and its host coming and going: nothing missed, nothing applied
/// twice, and no message ever sent to the agent twice, whatever retries.
@Suite("Host reconnects, end to end", .serialized, .timeLimit(.minutes(1)))
struct HostReconnectTests {
    @Test("A dropped connection re-attaches without missing or repeating an event")
    func reattachWithoutGaps() async throws {
        let harness = try HostHarness()
        try harness.start()
        let transport = CuttableTransport(location: harness.location)
        let recorder = try await harness.connect(transport: transport)
        let session = try await recorder.client.newSession(NewSessionParams(agentID: "fake", cwd: "/tmp", attach: true))
        _ = try await recorder.client.prompt(PromptParams(sessionID: session.id, text: "slow 8"))
        try await recorder.wait("the turn to get going") { await $0.agentText(session.id).contains("tick 2") }
        transport.cut()
        try await recorder.wait("the turn to end") { await $0.turnsEnded(session.id) == ["end_turn"] }
        let seqs = await recorder.events[session.id, default: []].map(\.seq)
        #expect(seqs == Array(1...(seqs.last ?? 0)))
        #expect(await recorder.agentText(session.id) == (1...8).map { "tick \($0)\n" }.joined())
        await recorder.stop()
    }

    @Test("A prompt sent while the host is down goes out once it's back, and only once")
    func promptWaitsForTheHost() async throws {
        let harness = try HostHarness()
        try harness.start()
        let recorder = try await harness.connect()
        let session = try await recorder.client.newSession(NewSessionParams(agentID: "fake", cwd: "/tmp", attach: true))
        harness.kill()
        let client = recorder.client
        let sending = Task { try await client.prompt(PromptParams(sessionID: session.id, text: "after")) }
        try await Task.sleep(for: .milliseconds(700))
        try harness.start()
        // Re-attaching reloads the session in the new host, and a message that arrives meanwhile
        // waits for the load: queued, then sent.
        #expect(try await [.prompted, .queued].contains(sending.value))
        try await recorder.wait("the turn") { await $0.turnsEnded(session.id) == ["end_turn"] }
        #expect(harness.received == ["prompt\tafter"])
        await recorder.stop()
    }

    @Test("Resending a request id after the host restarted gets the first answer and sends nothing")
    func requestIDSurvivesHostRestart() async throws {
        let harness = try HostHarness()
        try harness.start()
        let first = try await harness.connect()
        let session = try await first.client.newSession(NewSessionParams(agentID: "fake", cwd: "/tmp", attach: true))
        let request = PromptParams(sessionID: session.id, text: "slow 20")
        #expect(try await first.client.prompt(request) == .prompted)
        try await first.wait("the turn to get going") { await $0.agentText(session.id).contains("tick 1") }
        harness.kill()
        await first.stop()

        try harness.start()
        let second = try await harness.connect()
        try await second.client.attach(session.id)
        #expect(try await second.client.prompt(request) == .prompted)
        try await second.wait("the resumed turn", timeout: .seconds(30)) {
            await $0.turnsEnded(session.id) == ["end_turn"]
        }
        let received = harness.received
        #expect(received.filter { $0 == "prompt\tslow 20" }.count == 1)
        #expect(received.last?.hasPrefix("prompt\t[Native] Your previous turn was interrupted") == true)
        await second.stop()
    }

    @Test("Two copies of one steer arriving together are delivered once, and both get its answer")
    func concurrentDuplicates() async throws {
        let harness = try HostHarness()
        try harness.start()
        let recorder = try await harness.connect()
        let session = try await recorder.client.newSession(NewSessionParams(agentID: "fake", cwd: "/tmp", attach: true))
        _ = try await recorder.client.prompt(PromptParams(sessionID: session.id, text: "slow 5"))
        try await recorder.wait("the turn to get going") { await $0.agentText(session.id).contains("tick 1") }
        let steer = PromptParams(sessionID: session.id, text: "also", behavior: .steer)
        let client = recorder.client
        async let one = client.prompt(steer)
        async let two = client.prompt(steer)
        #expect(try await [one, two] == [.steered, .steered])
        try await recorder.wait("the turn") { await $0.turnsEnded(session.id) == ["end_turn"] }
        #expect(harness.received.filter { $0 == "steer\talso" }.count == 1)
        await recorder.stop()
    }
}
