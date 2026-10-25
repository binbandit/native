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

    @Test("A turn that ends while the client is away reads idle once it's back, its events once")
    func turnEndsWhileAway() async throws {
        let harness = try HostHarness()
        try harness.start()
        let transport = CuttableTransport(location: harness.location)
        let recorder = try await harness.connect(transport: transport)
        let session = try await recorder.client.newSession(NewSessionParams(agentID: "fake", cwd: "/tmp", attach: true))
        _ = try await recorder.client.prompt(PromptParams(sessionID: session.id, text: "slow 5"))
        try await recorder.wait("the turn to get going") { await $0.agentText(session.id).contains("tick 1") }
        #expect(await recorder.summaries[session.id]?.phase == .prompting)

        transport.goOffline()
        let observer = try await harness.connect()
        try await observer.wait("the turn to end on the host") {
            await $0.listed(session.id)?.phase == .idle
        }
        transport.goOnline()

        try await recorder.wait("the client to see the session idle") {
            await $0.summaries[session.id]?.phase == .idle
        }
        #expect(await recorder.summaries[session.id]?.lastStopReason == "end_turn")
        #expect(await recorder.turnsEnded(session.id) == ["end_turn"])
        let seqs = await recorder.events[session.id, default: []].map(\.seq)
        #expect(seqs == Array(1...(seqs.last ?? 0)))
        #expect(await recorder.agentText(session.id) == (1...5).map { "tick \($0)\n" }.joined())
        await observer.stop()
        await recorder.stop()
    }

    @Test("An approval asked while the client is away shows once it's back, asked once")
    func approvalWhileAway() async throws {
        let harness = try HostHarness()
        try harness.start()
        let transport = CuttableTransport(location: harness.location)
        let recorder = try await harness.connect(transport: transport)
        let session = try await recorder.client.newSession(NewSessionParams(agentID: "fake", cwd: "/tmp", attach: true))

        transport.goOffline()
        // Another client (the droid's own Native, a phone) starts a turn that asks.
        let observer = try await harness.connect()
        _ = try await observer.client.prompt(PromptParams(sessionID: session.id, text: "permission"))
        try await observer.wait("the host to wait for an answer") {
            await $0.listed(session.id)?.needsApproval == true
        }
        transport.goOnline()

        try await recorder.wait("the client to see the approval") {
            await $0.summaries[session.id]?.needsApproval == true
        }
        #expect(await recorder.summaries[session.id]?.phase == .prompting)
        let asked = await recorder.payloads(session.id).filter {
            if case .permissionRequested = $0 { true } else { false }
        }
        #expect(asked.count == 1)
        await observer.stop()
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
