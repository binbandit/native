import Foundation
import NativeHostClient
import NativeHostProtocol

@testable import NativeHost

/// Real clients and agents, with command cleanup held open independently of process timing.
@HostActor
final class HostStopCommandRig {
    let harness: HostHarness
    let core: HostCore
    let exits = Recorded<Int32>()

    init() throws {
        let harness = try HostHarness()
        self.harness = harness
        let exits = exits
        core = try HostCore(
            configuration: HostCore.Configuration(
                location: harness.location,
                hostInfo: PeerInfo(name: "test", version: "1", build: "1"),
                machineName: "test", bootTime: nil, environment: { ProcessInfo.processInfo.environment },
                pluginsDirectory: harness.plugins, exit: { exits.append($0) }))
    }

    func connect() async throws -> Recorder {
        try await harness.connect(transport: InProcessTransport { [core] stream in await core.accept(stream) })
    }

    /// A pending cleanup in the initial snapshot. Its release lets that drain pass finish after
    /// another client's Stop is accepted, without adding a hook to the host's process termination.
    func holdCleanup() -> AsyncStream<Void>.Continuation {
        let barrier = HostSession(
            record: StoredSession(
                id: HostSessionID(), agentID: "fake", agentSessionID: nil, cwd: harness.root.path,
                parentID: nil, origin: .user),
            agentName: "Fake Agent", phase: .idle, needsLoad: false, mcpServers: [])
        let (stream, release) = AsyncStream.makeStream(of: Void.self)
        core.stoppingSessions[barrier.id] = barrier
        barrier.stopTimeout = Task { [core] in
            for await _ in stream {}
            core.stoppingSessions[barrier.id] = nil
        }
        return release
    }

    func cleanup() {
        for session in core.stoppingSessions.values { session.stopTimeout?.cancel() }
        for client in core.clients.values { client.peer.close() }
        for agent in core.agents.values { agent.endNow() }
        harness.cleanup()
    }
}
