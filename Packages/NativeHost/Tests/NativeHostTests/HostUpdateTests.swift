import ACP
import Foundation
import NativeHostClient
import NativeHostProtocol
import Synchronization
import Testing

@testable import NativeHost

/// Remote updates (docs/releasing.md): who may do what, and how a Mac host relays to Native.app.
@Suite("Host updates", .serialized, .timeLimit(.minutes(1)))
@HostActor
struct HostUpdateTests {
    nonisolated static let release = HostUpdateStatus.Release(version: "1.4.0", build: "140")
    nonisolated static let current = HostUpdateStatus.Build(version: "1.3.0", build: "130", channel: "stable")
    nonisolated static let device = ClientGrants(managePlugins: false, manageHost: true, isLocal: false)
    nonisolated static let viewer = ClientGrants(managePlugins: false, manageHost: false, isLocal: false)

    /// An in-process host with `updates`, recording how it exits.
    final class Rig: Sendable {
        let exits = Recorded<Int32>()
        let core: HostCore
        let root = FileManager.default.temporaryDirectory.appending(path: "updates-\(UUID().uuidString.prefix(8))")

        @HostActor
        init(_ updates: HostUpdateEnvironment) throws {
            let exits = exits
            core = try HostCore(
                configuration: HostCore.Configuration(
                    location: HostLocation(directory: root),
                    hostInfo: PeerInfo(name: "test", version: "1.3.0", build: "130"),
                    machineName: "test", bootTime: nil, environment: { [:] }, heartbeatInterval: .milliseconds(50),
                    updates: updates, exit: { status in exits.append(status) }))
            core.start()
        }

        deinit {
            try? FileManager.default.removeItem(at: root)
        }

        /// A client with `grants` and everything it hears.
        @HostActor
        func connect(_ grants: ClientGrants, name: String) async throws -> (NativeHostClient, Heard) {
            let core = core
            let client = NativeHostClient(
                transport: InProcessTransport { stream in await core.accept(stream, grants: grants) },
                clientInfo: PeerInfo(name: name, version: "1", build: "1"))
            let heard = Heard()
            Task { for await event in client.events { heard.add(event) } }
            await client.start()
            _ = try await client.connected()
            return (client, heard)
        }

        func waitForExit() async throws -> Int32? {
            for _ in 0..<100 {
                if let status = exits.values.first { return status }
                try await Task.sleep(for: .milliseconds(20))
            }
            return nil
        }
    }

    final class Heard: Sendable {
        private let events = Mutex<[NativeHostClient.Event]>([])
        func add(_ event: NativeHostClient.Event) { events.withLock { $0.append(event) } }
        var installRequests: [HostUpdateStatus.When] {
            events.withLock {
                $0.compactMap { if case .appUpdateInstallRequested(let when) = $0 { when } else { nil } }
            }
        }
    }

    final class FakeUpdater: HostSelfUpdater {
        let activated = Mutex<[String]>([])
        let failActivation: Bool
        init(failActivation: Bool = false) { self.failActivation = failActivation }
        func checkAndStage() async throws -> HostUpdateStatus.Release? { HostUpdateTests.release }
        func activate(build: String) throws {
            if failActivation { throw HostUpdateErrorStub.diskFull }
            activated.withLock { $0.append(build) }
        }
        func lastRollback() -> HostUpdateStatus.Rollback? { nil }
    }

    enum HostUpdateErrorStub: Error { case diskFull }

    private func standalone(_ updater: FakeUpdater = FakeUpdater()) -> HostUpdateEnvironment {
        HostUpdateEnvironment(provider: .standalone, current: Self.current, selfUpdater: updater)
    }

    /// Waits until the host's check has found the release.
    private func ready(_ client: NativeHostClient) async throws {
        _ = try await client.checkForUpdate()
        for _ in 0..<100 where try await client.updateStatus().state != .ready {
            try await Task.sleep(for: .milliseconds(20))
        }
    }

    @Test("Anyone may read and check; only the manage-host grant installs; only local clients report")
    func authorization() async throws {
        let cases: [(ClientGrants, canInstall: Bool, canReport: Bool)] = [
            (.owner, true, true), (Self.device, true, false), (Self.viewer, false, false),
        ]
        for (grants, canInstall, canReport) in cases {
            let rig = try Rig(standalone())
            let (client, _) = try await rig.connect(grants, name: "device")
            try await ready(client)
            #expect(try await client.updateStatus().canInstall == canInstall)
            let report = HostUpdateStatus(provider: .app, current: Self.current, state: .upToDate)
            if canReport {
                try await client.reportUpdateStatus(report)
            } else {
                await #expect(throws: RPCError.self) { try await client.reportUpdateStatus(report) }
            }
            if canInstall {
                _ = try await client.installUpdate(.idle)
                #expect(try await rig.waitForExit() == HostCore.ExitStatus.restart)
            } else {
                await #expect(throws: RPCError.self) { _ = try await client.installUpdate(.idle) }
                #expect(rig.exits.values.isEmpty)
            }
            await client.stop()
        }
    }

    @Test("A standalone host activates the staged build and exits for its supervisor; a failed swap stays put")
    func standaloneInstall() async throws {
        let updater = FakeUpdater()
        let rig = try Rig(standalone(updater))
        let (client, _) = try await rig.connect(.owner, name: "Native")
        try await ready(client)
        _ = try await client.installUpdate(.now)
        #expect(try await rig.waitForExit() == HostCore.ExitStatus.restart)
        #expect(updater.activated.withLock { $0 } == ["140"])

        let failing = try Rig(standalone(FakeUpdater(failActivation: true)))
        let (other, _) = try await failing.connect(.owner, name: "Native")
        try await ready(other)
        _ = try await other.installUpdate(.now)
        try await Task.sleep(for: .milliseconds(200))
        #expect(failing.exits.values.isEmpty)
        #expect(try await other.updateStatus().state == .failed)
        await client.stop()
        await other.stop()
    }

    @Test(
        "On a Mac the host relays installs to Native.app, opens it when it isn't running, and restarts onto the new bundle"
    )
    func appRelay() async throws {
        let opened = Mutex(0)
        let onDisk = Mutex("130")
        let updates = HostUpdateEnvironment(
            provider: .app, current: Self.current, openAppToInstall: { opened.withLock { $0 += 1 } },
            installedBuild: { onDisk.withLock { $0 } })
        let rig = try Rig(updates)
        let (app, appHeard) = try await rig.connect(.owner, name: "Native")
        let (phone, _) = try await rig.connect(Self.device, name: "Brayden's iPhone")
        // Nothing to install until the app's updater says so.
        await #expect(throws: RPCError.self) { _ = try await phone.installUpdate(.idle) }
        try await app.reportUpdateStatus(
            HostUpdateStatus(
                provider: .app, current: Self.current, state: .available, available: Self.release, canInstall: true))
        let seen = try await phone.updateStatus()
        #expect(seen.state == .available && seen.canInstall && seen.available == Self.release)

        _ = try await phone.installUpdate(.now)
        for _ in 0..<100 where appHeard.installRequests.isEmpty { try await Task.sleep(for: .milliseconds(20)) }
        #expect(appHeard.installRequests == [.now])
        #expect(opened.withLock { $0 } == 0)
        #expect(
            try rig.core.store.activity(after: nil, limit: 10).contains {
                $0.kind == .updateRequested
                    && $0.detail?.hasPrefix("Brayden's iPhone asked to install Native 1.4.0 now") == true
            })

        // With the app gone, the host opens it to install.
        await app.stop()
        try await Task.sleep(for: .milliseconds(100))
        _ = try await phone.installUpdate(.now)
        for _ in 0..<100 where opened.withLock({ $0 }) == 0 { try await Task.sleep(for: .milliseconds(20)) }
        #expect(opened.withLock { $0 } == 1)

        // The update replaced the bundle: the host restarts onto it.
        #expect(rig.exits.values.isEmpty)
        onDisk.withLock { $0 = "140" }
        #expect(try await rig.waitForExit() == HostCore.ExitStatus.restart)
        await phone.stop()
    }
}

final class Recorded<Value: Sendable>: Sendable {
    private let storage = Mutex<[Value]>([])
    func append(_ value: Value) { storage.withLock { $0.append(value) } }
    var values: [Value] { storage.withLock { $0 } }
}
