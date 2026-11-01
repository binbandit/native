import Foundation
import NativeHostProtocol
import Synchronization
import Testing

@testable import NativeHost

@Suite(.timeLimit(.minutes(1))) @HostActor
struct HostConfigReplyTests {
    @Test(arguments: [false, true])
    func restartWaitsForOutboundSettingsReply(stalled: Bool) async throws {
        let rig = try HostStopCommandRig()
        defer { rig.cleanup() }
        let stream = Mutex<GatedConfigReplyStream?>(nil)
        let recorder = try await rig.harness.connect(
            transport: InProcessTransport { raw in
                let gated = GatedConfigReplyStream(raw)
                stream.withLock { $0 = gated }
                await rig.core.accept(gated)
            })
        let session = try await recorder.client.newSession(
            NewSessionParams(agentID: "fake", cwd: rig.harness.root.path))
        let gated = try #require(stream.withLock { $0 })
        gated.hold()
        let model = Task {
            try await recorder.client.setConfigOption(
                SetConfigOptionParams(sessionID: session.id, configID: "model", value: "beta"))
        }
        try await recorder.wait("settings applied with their reply still queued") { _ in
            let applied = await rig.core.sessions[session.id]?.record.configChoices["model"] == "beta"
            let completed = await rig.core.sessions[session.id]?.configChange == nil
            return applied && completed
        }
        await rig.core.shutdown(stopAgents: false, immediately: false)
        #expect(rig.exits.values.isEmpty)
        rig.core.exitIfIdleForRestart()
        #expect(rig.exits.values.isEmpty)
        if stalled {
            try await recorder.wait("the bounded reply drain to expire") { _ in rig.exits.values == [75] }
        }
        gated.release()
        try await model.value
        try await recorder.wait("restart after reply drain") { _ in rig.exits.values == [75] }
        await recorder.stop()
    }
}

private final class GatedConfigReplyStream: ByteStream {
    private struct State {
        var holding = false
        var pending = Data()
    }
    private let state = Mutex(State())
    private let raw: any ByteStream

    init(_ raw: any ByteStream) { self.raw = raw }
    func incoming() -> AsyncStream<Data> { raw.incoming() }
    func close() { raw.close() }
    func hold() { state.withLock { $0.holding = true } }
    func release() {
        state.withLock {
            $0.holding = false
            if !$0.pending.isEmpty { raw.write($0.pending) }
            $0.pending = Data()
        }
    }
    func write(_ data: Data) -> Bool {
        state.withLock {
            if $0.holding {
                $0.pending.append(data)
                return true
            }
            return raw.write(data)
        }
    }
    func flushed(timeout: Duration) async {
        let deadline = ContinuousClock.now + timeout
        while state.withLock({ $0.holding }), !Task.isCancelled, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(5))
        }
    }
}
