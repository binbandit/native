import ACP
import Foundation
import NativeHostClient
import NativeHostProtocol
import SessionTitling
import Synchronization
import Testing

@testable import NativeHost

/// Titles in the host (docs/durability.md, "Titles"): written with no client attached, the user's
/// renames winning, and nothing lost to a restart.
@Suite("Host titles", .serialized, .timeLimit(.minutes(1)))
@HostActor
struct HostTitleTests {
    /// Writes titles on cue: each request waits until the test lets it through, then answers
    /// `answer` (nil is a machine with no model).
    final class ScriptedTitler: SessionTitleGenerator {
        struct Script {
            var answer: String?
            var isReleased: Bool
            var requests: [SessionTitleRequest] = []
        }

        let script: Mutex<Script>

        init(answer: String?, released: Bool = true) {
            script = Mutex(Script(answer: answer, isReleased: released))
        }

        func release() {
            script.withLock { $0.isReleased = true }
        }

        var requests: [SessionTitleRequest] {
            script.withLock { $0.requests }
        }

        func title(for request: SessionTitleRequest) async throws -> String? {
            script.withLock { $0.requests.append(request) }
            while !script.withLock({ $0.isReleased }) {
                try await Task.sleep(for: .milliseconds(20))
            }
            return script.withLock { $0.answer }
        }
    }

    /// Hosts in-process on one scratch store, running the fake agent.
    @HostActor
    final class Rig {
        let root = FileManager.default.temporaryDirectory.appending(
            path: "host-titles-\(UUID().uuidString.prefix(8))", directoryHint: .isDirectory)
        var project: URL { root.appending(path: "project-alpha", directoryHint: .isDirectory) }

        private final class BundleMarker {}

        /// Where this test bundle's own build put the fake agent, whatever the scratch path.
        private static let products = Bundle(for: BundleMarker.self).bundleURL.deletingLastPathComponent()

        var agent: AgentSpec {
            AgentSpec(
                id: "fake", name: "Fake Agent",
                command: Self.products.appending(path: "FakeACPAgent").path(percentEncoded: false),
                env: ["FAKE_AGENT_STORE": root.appending(path: "agent").path(percentEncoded: false)])
        }

        init() throws {
            try FileManager.default.createDirectory(
                at: root.appending(path: "agent"), withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        }

        deinit {
            try? FileManager.default.removeItem(at: root)
        }

        /// A host on the rig's store, started, as launchd would start it after any exit.
        func host(_ titler: (any SessionTitleGenerator)?) throws -> HostCore {
            let core = try HostCore(
                configuration: HostCore.Configuration(
                    location: HostLocation(directory: root.appending(path: "host", directoryHint: .isDirectory)),
                    hostInfo: PeerInfo(name: "test", version: "1", build: "1"), machineName: "test", bootTime: nil,
                    environment: { [:] }, exit: { _ in }, titleGenerator: titler))
            core.start()
            return core
        }

        func connect(
            to core: HostCore, grants: ClientGrants = .owner, syncingAgents: Bool = true
        ) async throws -> NativeHostClient {
            let client = NativeHostClient(
                transport: InProcessTransport { stream in await core.accept(stream, grants: grants) },
                clientInfo: PeerInfo(name: "tests", version: "1", build: "1"))
            await client.start()
            _ = try await client.connected()
            if syncingAgents {
                try await client.syncAgents([agent])
            }
            return client
        }

        func startTask(
            _ text: String, on client: NativeHostClient, in folder: URL? = nil
        ) async throws
            -> HostSessionID
        {
            let session = try await client.newSession(
                NewSessionParams(agentID: "fake", cwd: (folder ?? project).path(percentEncoded: false)))
            _ = try await client.prompt(PromptParams(sessionID: session.id, text: text))
            return session.id
        }
    }

    private func eventually(
        _ what: String, timeout: Duration = .seconds(15), _ condition: () throws -> Bool
    ) async throws {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if try condition() { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        Issue.record("Timed out waiting for \(what)")
    }

    @Test("A task gets its title with no client attached, written with the user's instructions")
    func titledWithNoClient() async throws {
        let rig = try Rig()
        let titler = ScriptedTitler(answer: "fix the login test.", released: false)
        let host = try rig.host(titler)
        let client = try await rig.connect(to: host)
        try await client.configureTitles(
            ConfigureTitlesParams(
                provider: .onDevice, instructions: HostTitleInstructions(global: "Prefer British spelling")))
        let session = try await rig.startTask("fix the flaky login test", on: client)
        try await eventually("the title to be asked for") { !titler.requests.isEmpty }
        await client.stop()
        try await eventually("the client to go") { host.clients.isEmpty }

        titler.release()
        try await eventually("the title") { host.sessions[session]?.titleState.generated != nil }
        #expect(try host.store.titles()[session]?.generated == "Fix the login test")
        let request = try #require(titler.requests.first)
        #expect(request.prompt == "fix the flaky login test")
        #expect(request.projectName == "project-alpha")
        #expect(request.instructions?.text == "Prefer British spelling")

        let later = try await rig.connect(to: host)
        let summary = try #require(try await later.sessions().first { $0.id == session })
        #expect(summary.titles == HostSessionTitles(generated: "Fix the login test"))
        await later.stop()
    }

    @Test("The user's title wins, undo goes back to the generated one, and the first generated title stays")
    func renameWins() async throws {
        let rig = try Rig()
        let titler = ScriptedTitler(answer: "Add retry to uploads", released: false)
        let host = try rig.host(titler)
        let client = try await rig.connect(to: host)
        try await client.configureTitles(ConfigureTitlesParams(provider: .onDevice))
        let session = try await rig.startTask("make uploads retry", on: client)

        // Renamed while the title is still being written.
        try await client.setSessionTitle(SetSessionTitleParams(sessionID: session, title: " Uploads ", source: .user))
        titler.release()
        try await eventually("the title") { host.sessions[session]?.titleState.generated != nil }
        let summary = try #require(try await client.sessions().first { $0.id == session })
        #expect(summary.titles?.user == "Uploads")
        #expect(host.sessions[session]?.displayTitle == "Uploads")

        // Undo puts the automatic title back.
        try await client.setSessionTitle(SetSessionTitleParams(sessionID: session, title: nil, source: .user))
        #expect(host.sessions[session]?.displayTitle == "Add retry to uploads")
        #expect(try host.store.titles()[session]?.user == nil)

        // A client's late title doesn't replace the one that landed, and later messages don't
        // title the task again.
        try await client.setSessionTitle(
            SetSessionTitleParams(sessionID: session, title: "Something else", source: .generated))
        _ = try await client.prompt(PromptParams(sessionID: session, text: "and add a test"))
        #expect(host.sessions[session]?.titleState.generated == "Add retry to uploads")
        #expect(titler.requests.count == 1)
        await client.stop()
    }

    @Test("Titles survive a restart, and one the host was writing when it stopped gets written")
    func restartRecovery() async throws {
        let rig = try Rig()
        let first = try rig.host(ScriptedTitler(answer: "Never written", released: false))
        let client = try await rig.connect(to: first)
        try await client.configureTitles(ConfigureTitlesParams(provider: .onDevice))
        let renamed = try await rig.startTask("rename me", on: client)
        try await client.setSessionTitle(SetSessionTitleParams(sessionID: renamed, title: "Mine", source: .user))
        let cutOff = try await rig.startTask("write the changelog", on: client)
        try await eventually("the title to start") { first.sessions[cutOff]?.titleState.progress == .generating }
        await client.stop()
        // The host goes away mid-title, as when it's killed: the first run writes nothing more.
        for link in first.agents.values {
            link.endNow()
        }

        let titler = ScriptedTitler(answer: "Write the changelog")
        let second = try rig.host(titler)
        try await eventually("the cut-off title") {
            second.sessions[cutOff]?.titleState.generated == "Write the changelog"
        }
        #expect(second.sessions[renamed]?.displayTitle == "Mine")
        #expect(second.titling.configuration.provider == .onDevice)
        #expect(Set(titler.requests.map(\.prompt)) == ["rename me", "write the changelog"])
    }

    @Test("With no model on the host, a client writes the title, and the first message names the task meanwhile")
    func clientWritesTitle() async throws {
        let rig = try Rig()
        let host = try rig.host(ScriptedTitler(answer: nil))
        let client = try await rig.connect(to: host)
        try await client.configureTitles(ConfigureTitlesParams(provider: .onDevice))
        let session = try await rig.startTask("summarize the open pull requests for this repo please", on: client)
        try await eventually("the host to ask clients") {
            host.sessions[session]?.titleState.progress == .waitingForClient
        }
        let waiting = try #require(try await client.sessions().first { $0.id == session })
        #expect(waiting.titles?.request?.prompt == "summarize the open pull requests for this repo please")
        #expect(waiting.titles?.fallback == "Summarize the open pull requests for this repo…")

        try await client.setSessionTitle(
            SetSessionTitleParams(sessionID: session, title: "Open pull request summary", source: .generated))
        let titled = try #require(try await client.sessions().first { $0.id == session })
        #expect(titled.titles == HostSessionTitles(generated: "Open pull request summary"))
        await client.stop()
    }

    @Test("A new task titled like another live task in its project is told apart; one elsewhere isn't")
    func distinctFromSiblings() async throws {
        let rig = try Rig()
        let titler = ScriptedTitler(answer: "Run shell command")
        let host = try rig.host(titler)
        let client = try await rig.connect(to: host)
        try await client.configureTitles(ConfigureTitlesParams(provider: .onDevice))
        let first = try await rig.startTask("run a shell command", on: client)
        try await eventually("the first title") { host.sessions[first]?.titleState.generated != nil }
        let second = try await rig.startTask("run a shell command", on: client)
        try await eventually("the second title") { host.sessions[second]?.titleState.generated != nil }
        #expect(host.sessions[first]?.displayTitle == "Run shell command")
        #expect(host.sessions[second]?.displayTitle == "Run shell command again")
        #expect(titler.requests.last?.otherTitles == ["Run shell command"])

        let elsewhere = rig.root.appending(path: "project-beta", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: elsewhere, withIntermediateDirectories: true)
        let other = try await rig.startTask("run a shell command", on: client, in: elsewhere)
        try await eventually("the other project's title") { host.sessions[other]?.titleState.generated != nil }
        #expect(host.sessions[other]?.displayTitle == "Run shell command")
        await client.stop()
    }

    @Test(
        "Only the owner or a device managing the host chooses who writes titles; a client-only titler or none leaves the host's unused"
    )
    func configuration() async throws {
        let rig = try Rig()
        let titler = ScriptedTitler(answer: "Unused")
        let host = try rig.host(titler)
        let viewer = try await rig.connect(
            to: host, grants: ClientGrants(managePlugins: false, manageHost: false, isLocal: false),
            syncingAgents: false)
        await #expect(throws: RPCError.self) {
            try await viewer.configureTitles(ConfigureTitlesParams(provider: .onDevice))
        }
        await viewer.stop()
        let pairedMac = try await rig.connect(
            to: host, grants: ClientGrants(managePlugins: false, manageHost: true, isLocal: false),
            syncingAgents: false)
        try await pairedMac.configureTitles(ConfigureTitlesParams(provider: .onDevice))
        #expect(host.titling.configuration.provider == .onDevice)
        await pairedMac.stop()

        let client = try await rig.connect(to: host)
        try await client.configureTitles(ConfigureTitlesParams(provider: .client))
        let clientTitled = try await rig.startTask("tidy the readme", on: client)
        try await eventually("the host to ask clients") {
            host.sessions[clientTitled]?.titleState.progress == .waitingForClient
        }
        try await client.configureTitles(ConfigureTitlesParams(provider: .off))
        let untitled = try await rig.startTask("bump the version", on: client)
        #expect(host.sessions[untitled]?.titleState.isEmpty == true)
        #expect(titler.requests.isEmpty)
        await client.stop()
    }
}
