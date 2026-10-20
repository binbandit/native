import Foundation
import NativeHostClient
import NativeHostProtocol
import Synchronization
import Testing

@testable import NativeHost

/// `_native/host/status`, keeping awake around a real turn of the fake agent, and the doctor through
/// the protocol, on an in-process host with a fake power backend and a fake machine.
@Suite("Host status and keeping awake", .serialized, .timeLimit(.minutes(1)))
@HostActor
struct HostStatusTests {
    static let viewer = ClientGrants(managePlugins: false, manageHost: false, isLocal: false)
    static let manager = ClientGrants(managePlugins: false, manageHost: true, isLocal: false)

    /// The fake agent, built beside these tests.
    nonisolated static let fakeAgent = Bundle(for: FakePowerBackend.self).bundleURL.deletingLastPathComponent()
        .appending(path: "FakeACPAgent").path(percentEncoded: false)

    final class Rig: Sendable {
        let root: URL
        let backend: FakePowerBackend
        let core: HostCore
        /// A rig restarting another's host leaves the folder to that one.
        private let ownsRoot: Bool

        var agent: AgentSpec {
            AgentSpec(
                id: "fake", name: "Fake Agent", command: HostStatusTests.fakeAgent,
                env: ["FAKE_AGENT_STORE": root.appending(path: "agent").path(percentEncoded: false)])
        }

        /// A host in a new folder, or (`restarting`) another one on that rig's store.
        @HostActor
        init(restarting other: Rig? = nil) throws {
            root =
                other?.root
                ?? FileManager.default.temporaryDirectory.appending(path: "status-\(UUID().uuidString.prefix(8))")
            ownsRoot = other == nil
            backend = FakePowerBackend()
            var machine = HostDoctorTests.readyMachine
            machine.executables.insert(HostStatusTests.fakeAgent)
            core = try HostCore(
                configuration: HostCore.Configuration(
                    location: HostLocation(directory: root.appending(path: "host")),
                    hostInfo: PeerInfo(name: "test", version: "1", build: "1"), machineName: "mini",
                    bootTime: Date(timeIntervalSince1970: 1_800_000_000), environment: { ["PATH": "/opt/bin"] },
                    exit: { _ in }, keepAwake: backend,
                    systemInfo: HostSystemInfo(system: "macOS 27.1", model: "Mac16,10", loadAverage: { 1.5 }),
                    doctor: HostDoctor(machine: machine, platform: nil)))
            core.start()
        }

        deinit {
            if ownsRoot {
                try? FileManager.default.removeItem(at: root)
            }
        }

        @HostActor
        func connect(_ grants: ClientGrants = .owner) async throws -> NativeHostClient {
            let core = core
            let client = NativeHostClient(
                transport: InProcessTransport { stream in await core.accept(stream, grants: grants) },
                clientInfo: PeerInfo(name: "tests", version: "1", build: "1"))
            await client.start()
            _ = try await client.connected()
            return client
        }
    }

    @Test("Status says what the machine runs, since when, how loaded, and how it's kept awake")
    func status() async throws {
        let rig = try Rig()
        let client = try await rig.connect()
        let status = try await client.hostStatus()
        #expect(status.system == "macOS 27.1")
        #expect(status.model == "Mac16,10")
        #expect(status.bootedAt == Date(timeIntervalSince1970: 1_800_000_000))
        #expect(status.loadAverage == 1.5)
        #expect(status.keepAwake.policy.mode == .off)
        #expect(status.keepAwake.isSupported)
        await client.stop()
    }

    @Test("The host holds the assertion while a session's turn runs and lets go once it's idle")
    func heldAroundATurn() async throws {
        let rig = try Rig()
        let client = try await rig.connect()
        let heard = Recorded<HostStatus>()
        await client.addStatusHandler { heard.append($0) }
        try await client.syncAgents([rig.agent])
        let state = try await client.setKeepAwake(KeepAwakePolicy(mode: .whileAgentsWork))
        #expect(state.status.reason == .waitingForAgents)
        #expect(rig.backend.held.isEmpty)

        let session = try await client.newSession(
            NewSessionParams(agentID: "fake", cwd: rig.root.path(percentEncoded: false)))
        _ = try await client.prompt(PromptParams(sessionID: session.id, text: "slow 3"))
        #expect(await HostKeepAwakeTests.eventually { rig.backend.held == HostKeepAwakeTests.awake })
        #expect(await HostKeepAwakeTests.eventually { heard.values.last?.keepAwake.status.reason == .agentsWorking })
        // The turn takes about a second; the assertion goes with it.
        #expect(await HostKeepAwakeTests.eventually(within: .seconds(10)) { rig.backend.held.isEmpty })
        #expect(await HostKeepAwakeTests.eventually { heard.values.last?.keepAwake.status.reason == .waitingForAgents })
        await client.stop()
    }

    @Test("Only the owner and devices that may manage the host set it, and it holds across a restart")
    func policy() async throws {
        let rig = try Rig()
        let viewer = try await rig.connect(Self.viewer)
        await #expect(throws: (any Error).self) {
            _ = try await viewer.setKeepAwake(KeepAwakePolicy(mode: .on))
        }
        #expect(rig.backend.held.isEmpty)
        let manager = try await rig.connect(Self.manager)
        _ = try await manager.setKeepAwake(KeepAwakePolicy(mode: .on))
        #expect(rig.backend.held == HostKeepAwakeTests.awake)
        await viewer.stop()
        await manager.stop()

        // A new host on the same store keeps the machine awake without any client asking.
        let restarted = try Rig(restarting: rig)
        #expect(restarted.core.keepAwake.policy.mode == .on)
        #expect(restarted.backend.held == HostKeepAwakeTests.awake)
        withExtendedLifetime(rig) {}
    }

    @Test("The doctor through the protocol checks the agents the host runs")
    func doctor() async throws {
        let rig = try Rig()
        let client = try await rig.connect()
        try await client.syncAgents([rig.agent, HostDoctorTests.codex])
        let report = try await client.doctor()
        #expect(report.isHostRunning)
        #expect(report.checks.first { $0.id == "agents.fake" }?.status == .ok)
        #expect(report.checks.first { $0.id == "agents.codex" }?.status == .failed)
        #expect(report.checks.first { $0.id == "host.keepAwake" }?.status == .info)
        await client.stop()
    }
}

/// A development host stops when idle, unless devices are paired with it: they reach it only while
/// it runs, so a droid running a development build would otherwise vanish under a closed laptop.
@Suite("Idle development hosts", .serialized, .timeLimit(.minutes(1)))
@HostActor
struct HostIdleExitTests {
    @Test("Paired devices keep an idle development host running")
    func pairedDevicesKeepItRunning() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "idle-\(UUID().uuidString.prefix(8))")
        defer { try? FileManager.default.removeItem(at: root) }
        let exits = Recorded<Int32>()
        let core = try HostCore(
            configuration: HostCore.Configuration(
                location: HostLocation(directory: root), hostInfo: PeerInfo(name: "test", version: "1", build: "1"),
                machineName: "mini", bootTime: nil, environment: { [:] }, heartbeatInterval: .milliseconds(20),
                idleExit: .zero, exit: { exits.append($0) }))
        core.hasPairedDevices = true
        core.start()
        try await Task.sleep(for: .milliseconds(200))
        #expect(exits.values.isEmpty)
        core.hasPairedDevices = false
        #expect(await HostKeepAwakeTests.eventually { exits.values == [HostCore.ExitStatus.stopped] })
    }
}
