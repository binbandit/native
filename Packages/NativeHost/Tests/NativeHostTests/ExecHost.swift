import Foundation
import NativeHostClient
import NativeHostProtocol
import Testing

@testable import NativeHost

/// A host in this process with a project folder it knows, and clients with whatever grants a test
/// needs, connected as a paired device would be after its handshake. Git run here sees an empty
/// config, so the user's hooks and signing can't reach the tests.
final class ExecHost: Sendable {
    let harness: HostHarness
    let core: HostCore
    /// The owner: local, with every grant. It listed `project`.
    let owner: NativeHostClient
    let project: URL
    /// Beside the project, where nothing may reach.
    let outside: URL

    var projectPath: String { project.path(percentEncoded: false) }

    static let environment: [String: String] = {
        var environment = ProcessInfo.processInfo.environment
        let emptyConfig = FileManager.default.temporaryDirectory.appending(path: "native-host-tests-empty.gitconfig")
        _ = FileManager.default.createFile(atPath: emptyConfig.path(percentEncoded: false), contents: Data())
        environment["GIT_CONFIG_GLOBAL"] = emptyConfig.path(percentEncoded: false)
        environment["GIT_CONFIG_NOSYSTEM"] = "1"
        environment["GIT_AUTHOR_NAME"] = "Test"
        environment["GIT_AUTHOR_EMAIL"] = "test@example.com"
        environment["GIT_COMMITTER_NAME"] = "Test"
        environment["GIT_COMMITTER_EMAIL"] = "test@example.com"
        environment["NATIVE_HOST_ONLY"] = "from the host"
        return environment
    }()

    private init(harness: HostHarness, core: HostCore, owner: NativeHostClient) {
        self.harness = harness
        self.core = core
        self.owner = owner
        project = harness.root.appending(path: "project", directoryHint: .isDirectory)
        outside = harness.root.appending(path: "outside", directoryHint: .isDirectory)
    }

    static func make() async throws -> ExecHost {
        let harness = try HostHarness()
        let core = try await HostCore(
            configuration: HostCore.Configuration(
                location: harness.location, hostInfo: PeerInfo(name: "test", version: "1", build: "1"),
                machineName: "test", bootTime: nil, environment: { ExecHost.environment },
                pluginsDirectory: harness.plugins,
                exit: { _ in }))
        let owner = try await connect(to: core, grants: .owner, name: "owner")
        let host = ExecHost(harness: harness, core: core, owner: owner)
        for folder in [host.project, host.outside] {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        _ = try await owner.addProject(host.projectPath)
        return host
    }

    /// Another client, as a paired device with `grants` would reach the host.
    func connect(_ grants: ClientGrants, name: String) async throws -> NativeHostClient {
        try await Self.connect(to: core, grants: grants, name: name)
    }

    private static func connect(to core: HostCore, grants: ClientGrants, name: String) async throws -> NativeHostClient
    {
        let transport = InProcessTransport { stream in
            await core.accept(stream, grants: grants)
        }
        let client = NativeHostClient(transport: transport, clientInfo: PeerInfo(name: name, version: "1", build: "1"))
        await client.start()
        _ = try await client.connected()
        return client
    }

    func stop() async {
        await owner.stop()
    }

    static let device = ClientGrants(managePlugins: false, manageHost: false, isLocal: false)
    static let commandingDevice = ClientGrants(
        managePlugins: false, manageHost: false, isLocal: false, runCommands: true)
}
