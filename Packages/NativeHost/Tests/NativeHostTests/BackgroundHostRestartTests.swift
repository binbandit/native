import ACP
import Foundation
import NativeHostClient
import NativeHostProtocol
import Testing

@Suite("Manual background host restart", .serialized, .timeLimit(.minutes(1)))
@MainActor
struct BackgroundHostRestartTests {
    @Test("Cancelling confirmation sends no shutdown and leaves running work alone")
    func cancel() async throws {
        let harness = try HostHarness()
        defer { harness.cleanup() }
        try harness.start()
        let recorder = try await harness.connect()
        let session = try await recorder.client.newSession(
            NewSessionParams(agentID: "fake", cwd: harness.root.path, attach: true))
        _ = try await recorder.client.prompt(PromptParams(sessionID: session.id, text: "slow 4"))
        try await recorder.wait("working before cancelling") { await $0.summaries[session.id]?.isWorking == true }
        let epoch = try #require(await recorder.client.hostInfo?.epoch)
        let model = BackgroundHostRestartModel()
        model.request()
        #expect(model.state == .confirming)
        model.cancel()
        #expect(model.state == .idle)
        #expect(try await harness.waitForExit(timeout: .milliseconds(150)) == nil)
        #expect(await recorder.client.hostInfo?.epoch == epoch)
        await recorder.stop()
    }

    @Test("Restart completes only when a new host reconnects, and its running task resumes")
    func runningTask() async throws {
        let harness = try HostHarness()
        defer { harness.cleanup() }
        try harness.start()
        let recorder = try await harness.connect()
        let session = try await recorder.client.newSession(
            NewSessionParams(agentID: "fake", cwd: harness.root.path, attach: true))
        _ = try await recorder.client.prompt(PromptParams(sessionID: session.id, text: "slow 20"))
        try await recorder.wait("working") { await $0.summaries[session.id]?.isWorking == true }
        let epoch = try #require(await recorder.client.hostInfo?.epoch)
        let model = BackgroundHostRestartModel()
        model.request()
        let restart = Task { await model.restart(using: recorder.client, whenIdle: false) }
        #expect(try await harness.waitForExit() == 75)
        #expect(model.state == .restarting)
        try harness.start()
        await restart.value
        guard case .done = model.state else { Issue.record("Restart did not finish: \(model.state)"); return }
        #expect(await recorder.client.hostInfo?.epoch != epoch)
        try await recorder.wait("resumed task") { !(await $0.recoveries(session.id)).isEmpty }
        #expect(await recorder.failures(session.id).isEmpty)
        await recorder.stop()
    }

    @Test("Waiting keeps a busy host alive until its work ends")
    func waitForIdle() async throws {
        let harness = try HostHarness()
        defer { harness.cleanup() }
        try harness.start()
        let recorder = try await harness.connect()
        let session = try await recorder.client.newSession(
            NewSessionParams(agentID: "fake", cwd: harness.root.path, attach: true))
        _ = try await recorder.client.prompt(PromptParams(sessionID: session.id, text: "slow 3"))
        try await recorder.wait("working") { await $0.summaries[session.id]?.isWorking == true }
        let model = BackgroundHostRestartModel()
        model.request()
        let restart = Task { await model.restart(using: recorder.client, whenIdle: true) }
        try await Task.sleep(for: .milliseconds(100))
        #expect(model.state == .waiting)
        model.request()
        #expect(model.isConfirmationPresented)
        await model.restart(using: recorder.client, whenIdle: true)
        #expect(!model.isConfirmationPresented)
        #expect(model.state == .waiting)
        model.request()
        #expect(try await harness.waitForExit(timeout: .milliseconds(150)) == nil)
        #expect(try await harness.waitForExit() == 75)
        try harness.start()
        await restart.value
        guard case .done = model.state else { Issue.record("Deferred restart did not finish"); return }
        #expect(!model.isConfirmationPresented)
        #expect(await recorder.recoveries(session.id).isEmpty)
        await recorder.stop()
    }

    @Test("A scheduled restart can be confirmed again and escalated without losing its result")
    func restartNowWhileWaiting() async throws {
        let harness = try HostHarness()
        defer { harness.cleanup() }
        try harness.start()
        let recorder = try await harness.connect()
        let session = try await recorder.client.newSession(
            NewSessionParams(agentID: "fake", cwd: harness.root.path, attach: true))
        _ = try await recorder.client.prompt(PromptParams(sessionID: session.id, text: "slow 100"))
        try await recorder.wait("working") { await $0.summaries[session.id]?.isWorking == true }
        let model = BackgroundHostRestartModel()
        model.request()
        let waiting = Task { await model.restart(using: recorder.client, whenIdle: true) }
        defer { waiting.cancel() }
        try await Task.sleep(for: .milliseconds(100))
        #expect(model.state == .waiting)
        model.request()
        #expect(model.isConfirmationPresented)
        model.cancel()
        #expect(!model.isConfirmationPresented)
        #expect(model.state == .waiting)
        #expect(try await harness.waitForExit(timeout: .milliseconds(100)) == nil)
        model.request()
        let immediate = Task { await model.restart(using: recorder.client, whenIdle: false) }
        defer { immediate.cancel() }
        #expect(try await harness.waitForExit(timeout: .seconds(5)) == 75)
        try harness.start()
        await immediate.value
        await waiting.value
        guard case .done = model.state else { Issue.record("Escalated restart did not finish"); return }
        try await recorder.wait("resumed task") { !(await $0.recoveries(session.id)).isEmpty }
        await recorder.stop()
    }

    @Test("An idle restart reconnects without opening or interrupting tasks")
    func idle() async throws {
        let harness = try HostHarness()
        defer { harness.cleanup() }
        try harness.start()
        let recorder = try await harness.connect()
        let model = BackgroundHostRestartModel()
        model.request()
        let restart = Task { await model.restart(using: recorder.client, whenIdle: false) }
        #expect(try await harness.waitForExit() == 75)
        try harness.start()
        await restart.value
        guard case .done = model.state else { Issue.record("Idle restart did not finish"); return }
        #expect(try await recorder.client.sessions().isEmpty)
        await recorder.stop()
    }

    @Test("An accepted restart that never reconnects fails instead of claiming success")
    func reconnectTimeout() async throws {
        let harness = try HostHarness()
        defer { harness.cleanup() }
        try harness.start()
        let recorder = try await harness.connect()
        let model = BackgroundHostRestartModel()
        model.request()
        await model.restart(using: recorder.client, whenIdle: false, timeout: .milliseconds(250))
        #expect(try await harness.waitForExit() == 75)
        guard case .failed(let message) = model.state else { Issue.record("Missing reconnect failure"); return }
        #expect(message.contains("hasn't reconnected"))
        await recorder.stop()
    }

    @Test("A host that never answers shutdown times out without hanging the action")
    func unansweredRequest() async throws {
        let transport = RestartSilentTransport()
        let client = NativeHostClient(
            transport: transport, clientInfo: PeerInfo(name: "tests", version: "1", build: "1"))
        await client.start()
        _ = try await client.connected()
        let model = BackgroundHostRestartModel()
        model.request()
        await model.restart(using: client, whenIdle: false, timeout: .milliseconds(150))
        guard case .failed(let message) = model.state else { Issue.record("Missing request timeout"); return }
        #expect(message.contains("didn't answer"))
        await client.stop()
        await transport.stop()
    }

    @Test("A disconnected host fails plainly and can be requested again")
    func failure() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "restart-missing-\(UUID())")
        let client = NativeHostClient(
            transport: LocalSocketTransport(location: HostLocation(directory: root)),
            clientInfo: PeerInfo(name: "tests", version: "1", build: "1"))
        let model = BackgroundHostRestartModel()
        model.request()
        await model.restart(using: client, whenIdle: false)
        guard case .failed = model.state else { Issue.record("Missing failure"); return }
        model.request()
        #expect(model.state == .confirming)
        model.cancel()
        await client.stop()
    }
}

/// Answers the frozen handshake but deliberately never answers shutdown.
private actor RestartSilentTransport: HostTransport {
    nonisolated let displayName = "Silent restart fixture"
    private var peer: JSONRPCPeer?

    func connect() async throws -> any ByteStream {
        let (clientEnd, hostEnd) = try UnixSocket.pair()
        let peer = JSONRPCPeer(channel: ByteChannel.socket(hostEnd, label: "silent-restart"), label: "silent-restart") {
            [weak self] event in
            if case .request(let message) = event { await self?.receive(message) }
        }
        self.peer = peer
        peer.start()
        return ByteChannel.socket(clientEnd, label: "silent-restart-client")
    }

    private func receive(_ message: JSONRPCPeer.Message) {
        guard message.method == HostProtocol.Method.initialize, let id = message.id else { return }
        try? peer?.respond(
            to: id,
            with: HostInfo(
                protocolVersion: HostProtocol.version, hostID: HostID(), machineName: displayName,
                hostInfo: PeerInfo(name: "Native Host", version: "1", build: "1"), epoch: UUID(),
                processID: 1, startedAt: .now, channel: "tests"))
    }

    func stop() { peer?.close() }
}
