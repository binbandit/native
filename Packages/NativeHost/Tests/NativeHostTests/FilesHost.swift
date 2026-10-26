import Foundation
import NativeHostClient
import NativeHostProtocol
import Synchronization
import Testing

@testable import NativeHost

/// A host in this process with a project it knows and a folder beside it that's off limits, as
/// `ExecHost` sets up, with the watcher the test picks.
final class FilesHost: Sendable {
    let harness: HostHarness
    let core: HostCore
    /// The owner: local, with every grant.
    let owner: NativeHostClient
    let project: URL
    let outside: URL

    var projectPath: String { plainPath(project) }

    private init(harness: HostHarness, core: HostCore, owner: NativeHostClient) {
        self.harness = harness
        self.core = core
        self.owner = owner
        project = harness.root.appending(path: "project", directoryHint: .isDirectory)
        outside = harness.root.appending(path: "outside", directoryHint: .isDirectory)
    }

    static func make(watching: (any FileWatching)? = nil) async throws -> FilesHost {
        let harness = try HostHarness()
        let core = try await HostCore(
            configuration: HostCore.Configuration(
                location: harness.location, hostInfo: PeerInfo(name: "test", version: "1", build: "1"),
                machineName: "test", bootTime: nil, environment: { [:] }, pluginsDirectory: harness.plugins,
                exit: { _ in }, fileWatching: watching))
        let owner = try await connect(to: core, grants: .owner)
        let host = FilesHost(harness: harness, core: core, owner: owner)
        for folder in [host.project, host.outside] {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        _ = try await owner.addProject(host.projectPath)
        return host
    }

    func connect(_ grants: ClientGrants) async throws -> NativeHostClient {
        try await Self.connect(to: core, grants: grants)
    }

    func watchCount() async -> Int {
        await Self.watchCount(core)
    }

    func stop() async {
        await owner.stop()
    }

    /// How many folders the host's clients watch.
    static func watchCount(_ core: HostCore) async -> Int {
        await Task { @HostActor in core.clients.values.reduce(0) { $0 + $1.fileWatches.count } }.value
    }

    private static func connect(to core: HostCore, grants: ClientGrants) async throws -> NativeHostClient {
        let transport = InProcessTransport { stream in await core.accept(stream, grants: grants) }
        let client = NativeHostClient(
            transport: transport, clientInfo: PeerInfo(name: "test", version: "1", build: "1"))
        await client.start()
        _ = try await client.connected()
        return client
    }
}

/// A watcher the test drives: it records the folders the host watches and sends what it's told to.
final class ScriptedFileWatching: FileWatching {
    private let watches = Mutex<[UUID: (root: String, continuation: AsyncStream<FileWatchBatch>.Continuation)]>([:])

    func changes(under root: String) async -> AsyncStream<FileWatchBatch> {
        let (stream, continuation) = AsyncStream.makeStream(of: FileWatchBatch.self)
        let id = UUID()
        watches.withLock { $0[id] = (root, continuation) }
        continuation.onTermination = { [weak self] _ in
            self?.watches.withLock { $0[id] = nil }
        }
        return stream
    }

    var activeCount: Int { watches.withLock(\.count) }

    /// The folder being watched, once the host watches one.
    func root() async throws -> String {
        try await pollUntil("the host to watch") { self.activeCount > 0 }
        return try #require(watches.withLock { $0.values.first?.root })
    }

    func send(_ batch: FileWatchBatch) {
        for watch in watches.withLock({ Array($0.values) }) {
            watch.continuation.yield(batch)
        }
    }
}

/// Polls until `condition` holds, failing after `timeout`.
func pollUntil(
    _ what: String, timeout: Duration = .seconds(10), _ condition: @Sendable () async throws -> Bool
) async throws {
    let deadline = ContinuousClock.now + timeout
    while ContinuousClock.now < deadline {
        if try await condition() { return }
        try await Task.sleep(for: .milliseconds(20))
    }
    Issue.record("Timed out waiting for \(what)")
    throw CancellationError()
}

func plainPath(_ url: URL) -> String {
    let path = url.path(percentEncoded: false)
    return path.count > 1 && path.hasSuffix("/") ? String(path.dropLast()) : path
}
