import ACP
import Foundation
import NativeHostClient
import NativeHostProtocol
import Synchronization
import Testing

@testable import NativeHost

/// Signing an agent in on a host nobody sits at: keys the host keeps, a device code shown until the
/// user signs in elsewhere, and checking again. Drives the fake agent's sign-in
/// (`FAKE_AGENT_SIGN_IN`, FakeAgent+SignIn.swift) through a host in this process, so clients can
/// have any grants.
@Suite("Signing in on a host", .serialized, .timeLimit(.minutes(2)))
struct HostSignInTests {
    @Test("An API key goes to the agent, is kept on the host, and never comes back to any client")
    func apiKey() async throws {
        let host = try await SignInHost.make()
        let watcher = try await host.connect(.owner)
        let heard = await HostEventLog.listening(to: watcher)
        _ = try await host.owner.startAgent("fake")

        let agent = try await host.owner.setAgentCredential("fake", methodID: "key", secret: "test-key-0001")

        #expect(agent.savedCredentials == ["key"])
        #expect(agent.authStatus == AgentAuthStatus(kind: .apiKey, label: "Fake API key"))
        #expect(host.agentFile("key") == "test-key-0001")
        #expect(try host.savedFilePermissions() == 0o600)
        let everything = [
            String(decoding: try JSONEncoder().encode(try await host.owner.agents()), as: UTF8.self),
            String(decoding: try JSONEncoder().encode(try await host.owner.activity()), as: UTF8.self),
            await heard.text,
        ]
        for text in everything {
            #expect(!text.contains("test-key-0001"))
        }
        await host.stop()
    }

    @Test("A key the agent refuses isn't kept, and its error never repeats the key")
    func refusedKey() async throws {
        let host = try await SignInHost.make()

        let refused = await #expect(throws: RPCError.self) {
            _ = try await host.owner.setAgentCredential("fake", methodID: "key", secret: "bad-key-0001")
        }

        #expect(refused?.message == "The API key <key> was refused.")

        #expect(try await host.owner.agents().first?.savedCredentials == [])
        #expect(try host.savedCredentials().isEmpty)
        await host.stop()
    }

    @Test("Saving or removing a key takes manageHost; a device without it changes nothing")
    func keysNeedManageHost() async throws {
        let host = try await SignInHost.make()
        let device = try await host.connect(ClientGrants(managePlugins: true, manageHost: false, isLocal: false))

        let saving = await #expect(throws: RPCError.self) {
            _ = try await device.setAgentCredential("fake", methodID: "key", secret: "test-key-0002")
        }
        let removing = await #expect(throws: RPCError.self) {
            _ = try await device.removeAgentCredential("fake", methodID: "key")
        }

        #expect(saving.flatMap { HostErrorCode($0) } == .notAuthorized)
        #expect(removing.flatMap { HostErrorCode($0) } == .notAuthorized)
        #expect(try host.savedCredentials().isEmpty)
        await device.stop()
        await host.stop()
    }

    @Test("A key for a variable starts the agent with it, again after the host restarts, until removed")
    func environmentKey() async throws {
        let host = try await SignInHost.make()
        _ = try await host.owner.startAgent("fake")

        let agent = try await host.owner.setAgentCredential("fake", methodID: "env-key", secret: "test-env-0001")

        #expect(agent.authMethods?.map(\.id) == ["token", "key", "env-key", "device"])
        #expect(agent.savedCredentials == ["env-key"])
        #expect(agent.authStatus?.kind == .apiKey)
        #expect(host.agentFile("env-key") == "test-env-0001")

        let restarted = try await host.restartingHost()
        try FileManager.default.removeItem(at: restarted.agentStore.appending(path: "signin-env-key"))
        #expect(try await restarted.owner.agents().first?.savedCredentials == ["env-key"])
        _ = try await restarted.owner.startAgent("fake")
        #expect(restarted.agentFile("env-key") == "test-env-0001")

        let removed = try await restarted.owner.removeAgentCredential("fake", methodID: "env-key")

        #expect(removed.savedCredentials == [])
        #expect(removed.authStatus?.kind == .signedOut)
        #expect(removed.needsSignIn)
        await restarted.stop()
    }

    @Test("Only methods that take a key take one, so a client can't set any other variable")
    func onlyDeclaredMethods() async throws {
        let host = try await SignInHost.make()

        for method in ["token", "device", "PATH", "NODE_OPTIONS"] {
            await #expect(throws: RPCError.self) {
                _ = try await host.owner.setAgentCredential("fake", methodID: method, secret: "test-key-0003")
            }
        }
        await #expect(throws: RPCError.self) {
            _ = try await host.owner.setAgentCredential("fake", methodID: "key", secret: "two\nlines")
        }

        #expect(try host.savedCredentials().isEmpty)
        await host.stop()
    }

    @Test("A device code shows its page and code until the user signs in, then the agent goes back")
    func deviceCode() async throws {
        let host = try await SignInHost.make()
        let before = try await host.owner.startAgent("fake")
        #expect(before.authMethods?.first { $0.id == "device" }?.kind == .link)

        let signingIn = Task { try await host.owner.authenticateAgent("fake", methodID: "device") }
        let link = try await host.until("the link") { try await host.owner.agents().first?.signInLink }

        #expect(link.url.absoluteString == "https://example.com/device")
        #expect(link.code == "ABCD-1234")
        #expect(link.message == "Sign in to Fake and enter this code: ABCD-1234")
        _ = FileManager.default.createFile(
            atPath: host.harness.agentStore.appending(path: "signin-device-approved").path(percentEncoded: false),
            contents: Data())
        let signedIn = try await signingIn.value

        #expect(signedIn.signInLink == nil)
        #expect(!signedIn.isSigningIn)
        #expect(signedIn.authStatus == AgentAuthStatus(kind: .account, label: "Fake Pro"))
        // Back to advertising what it always does: no device code.
        let advertised = try JSONDecoder().decode(
            InitializeResponse.self, from: JSONEncoder().encode(try #require(signedIn.initialize)))
        #expect(advertised.authMethods.map(\.id) == ["token", "key"])
        await host.stop()
    }

    @Test("Cancelling a device code ends the sign-in")
    func cancelDeviceCode() async throws {
        let host = try await SignInHost.make()
        let signingIn = Task { try await host.owner.authenticateAgent("fake", methodID: "device") }
        _ = try await host.until("the link") { try await host.owner.agents().first?.signInLink }

        let cancelled = try await host.owner.cancelAgentSignIn("fake")

        #expect(cancelled.signInLink == nil)
        await #expect(throws: RPCError.self) { _ = try await signingIn.value }
        #expect(try await host.owner.agents().first?.isSigningIn == false)
        await host.stop()
    }

    @Test("Check again restarts the agent and takes its fresh answer, after a sign-in done elsewhere")
    func checkAgain() async throws {
        let host = try await SignInHost.make()
        let before = try await host.owner.startAgent("fake")
        _ = FileManager.default.createFile(
            atPath: host.harness.agentStore.appending(path: "signin-account").path(percentEncoded: false),
            contents: Data())

        let checked = try await host.owner.checkAgentSignIn("fake")

        #expect(checked.processID != before.processID)
        #expect(checked.authStatus?.kind == .account)
        #expect(!checked.needsSignIn)
        await host.stop()
    }

    @Test("Nothing that restarts an agent cuts off its work: it says why and changes nothing")
    func busyAgent() async throws {
        let host = try await SignInHost.make()
        let session = try await host.owner.newSession(NewSessionParams(agentID: "fake", cwd: "/tmp"))
        _ = try await host.owner.prompt(PromptParams(sessionID: session.id, text: "slow 30"))
        _ = try await host.until("the turn to start") {
            try await host.owner.sessions().first { $0.id == session.id && $0.phase == .prompting }
        }

        let checking = await #expect(throws: RPCError.self) { _ = try await host.owner.checkAgentSignIn("fake") }
        let saving = await #expect(throws: RPCError.self) {
            _ = try await host.owner.setAgentCredential("fake", methodID: "env-key", secret: "test-env-0002")
        }

        #expect(checking.flatMap { HostErrorCode($0) } == .busy)
        #expect(
            checking?.message == "Fake Agent is working on 1 task on test. Check again when it finishes, or stop it.")
        #expect(saving.flatMap { HostErrorCode($0) } == .busy)
        #expect(try host.savedCredentials().isEmpty)
        await host.stop()
    }

    @Test("The portable store replaces its file whole, readable by this user only")
    func credentialFile() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "native-credentials-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = HostCredentialFile(directory: folder)
        let first = HostCredential(agentID: "a", methodID: "m", variable: "A_KEY", secret: "test-1")

        try store.save(first)
        try store.save(HostCredential(agentID: "a", methodID: "m", variable: "A_KEY", secret: "test-2"))
        try store.save(HostCredential(agentID: "b", methodID: "m", variable: nil, secret: "test-3"))
        try store.remove(agentID: "b", methodID: "m")

        #expect(try store.load() == [HostCredential(agentID: "a", methodID: "m", variable: "A_KEY", secret: "test-2")])
        let attributes = try FileManager.default.attributesOfItem(atPath: store.url.path(percentEncoded: false))
        #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
        #expect(
            try FileManager.default.contentsOfDirectory(atPath: folder.path(percentEncoded: false)) == [
                "credentials.json"
            ])
        #expect(!String(describing: first).contains("test-1"))
    }

    @Test(
        "A link's code comes from its message",
        arguments: [
            ("Sign in to ChatGPT and enter this code: WXYZ-98765", "WXYZ-98765"),
            ("Enter ABC-123-DEF at the page", "ABC-123-DEF"),
            ("Open the page to sign in", nil),
            ("Use the ACP protocol", nil),
        ])
    func linkCode(message: String, code: String?) throws {
        #expect(HostSignInLink(url: try #require(URL(string: "https://example.com")), message: message).code == code)
    }
}

/// A host in this process whose fake agent signs in, with its own credentials file.
final class SignInHost: Sendable {
    let harness: HostHarness
    let core: HostCore
    let owner: NativeHostClient

    /// What the fake agent's plugin declares besides what it advertises: a key in a variable, and
    /// its device code (offered only to clients that open links).
    static let declared = [
        AuthMethod(
            id: "env-key", name: "Key in the environment",
            kind: .environment([AuthMethod.Variable(name: "FAKE_AGENT_API_KEY")])),
        AuthMethod(id: "device", name: "Device code", kind: .link),
    ]

    private init(harness: HostHarness, core: HostCore, owner: NativeHostClient) {
        self.harness = harness
        self.core = core
        self.owner = owner
    }

    static func make(harness: HostHarness? = nil) async throws -> SignInHost {
        let harness = try harness ?? HostHarness()
        let core = try await HostCore(
            configuration: HostCore.Configuration(
                location: harness.location, hostInfo: PeerInfo(name: "test", version: "1", build: "1"),
                machineName: "test", bootTime: nil,
                environment: { ProcessInfo.processInfo.environment.filter { !$0.key.hasPrefix("FAKE_AGENT") } },
                pluginsDirectory: harness.plugins, exit: { _ in }))
        let owner = try await connect(to: core, grants: .owner, name: "owner")
        var spec = harness.agentSpec
        spec.env["FAKE_AGENT_SIGN_IN"] = "1"
        spec.authMethods = declared
        try await owner.syncAgents([spec])
        return SignInHost(harness: harness, core: core, owner: owner)
    }

    func connect(_ grants: ClientGrants) async throws -> NativeHostClient {
        try await Self.connect(to: core, grants: grants, name: "device")
    }

    /// A new host on the same folder and agent store, as after the host restarted.
    func restartingHost() async throws -> SignInHost {
        await stop()
        return try await Self.make(harness: harness)
    }

    var agentStore: URL { harness.agentStore }

    /// What the fake agent wrote to `signin-<name>` in its store.
    func agentFile(_ name: String) -> String? {
        try? String(contentsOf: agentStore.appending(path: "signin-\(name)"), encoding: .utf8)
    }

    /// What the host's credentials file holds.
    func savedCredentials() throws -> [HostCredential] {
        try HostCredentialFile(directory: harness.location.directory).load()
    }

    func savedFilePermissions() throws -> Int? {
        let path = HostCredentialFile(directory: harness.location.directory).url.path(percentEncoded: false)
        return (try FileManager.default.attributesOfItem(atPath: path)[.posixPermissions] as? NSNumber)?.intValue
    }

    /// Polls `value` until it isn't nil.
    func until<Value: Sendable>(
        _ what: String, timeout: Duration = .seconds(20), _ value: () async throws -> Value?
    ) async throws -> Value {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if let value = try await value() { return value }
            try await Task.sleep(for: .milliseconds(50))
        }
        Issue.record("Timed out waiting for \(what)")
        throw CancellationError()
    }

    func stop() async {
        await owner.stop()
        await core.endAgentsForTests()
    }

    private static func connect(
        to core: HostCore, grants: ClientGrants, name: String
    ) async throws
        -> NativeHostClient
    {
        let transport = InProcessTransport { stream in
            await core.accept(stream, grants: grants)
        }
        let client = NativeHostClient(transport: transport, clientInfo: PeerInfo(name: name, version: "1", build: "1"))
        await client.start()
        _ = try await client.connected()
        return client
    }
}

extension HostCore {
    /// Ends every agent process, so none outlives its test.
    fileprivate func endAgentsForTests() {
        for link in agents.values {
            link.endNow()
        }
    }
}

/// Everything a client heard, as JSON text, to search for what must never reach it.
actor HostEventLog {
    private var lines: [String] = []

    static func listening(to client: NativeHostClient) async -> HostEventLog {
        let log = HostEventLog()
        await client.addEventHandler { event in
            if case .agentChanged(let agent) = event, let data = try? JSONEncoder().encode(agent) {
                await log.append(String(decoding: data, as: UTF8.self))
            }
        }
        return log
    }

    private func append(_ line: String) {
        lines.append(line)
    }

    var text: String {
        lines.joined(separator: "\n")
    }
}
