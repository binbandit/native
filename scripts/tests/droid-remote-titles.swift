import ACP
import Foundation
import NativeHostClient
import NativeHostProtocol

@testable import Native
@testable import NativeLink

// Titles of tasks on a paired host with only `NativeRemoteHosts` on here (docs/durability.md,
// "Titles"): the host is configured to title them, a task gains its fallback and title while this
// Mac is away and keeps them across reconnects, a new pairing and a host restart, renames win, and
// pairings that can't configure the host leave it alone and keep the app's own titles. This Mac's
// host keeps today's default. Every host is a fake process behind fake transports; titles come
// from a fake titler.

private struct TitlesFailure: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

/// One host process: its tasks' summaries, and what it does with title configuration.
private actor TitlesHost {
    enum Configuring {
        /// Takes the configuration from a pairing that may manage it; refuses others, as hosts do.
        case grantsDecide
        /// An older host that has no titles: it doesn't know the method.
        case unknownMethod
    }

    let hostID = HostID()
    /// The key every pairing with this host pins, as pairing the same host again does.
    let hostKey = LinkIdentity().publicKey
    private(set) var epoch = UUID()
    private(set) var summaries: [HostSessionSummary] = []
    let configuring: Configuring
    private(set) var isDown = false
    private var links: [TitlesLink] = []
    /// The next generated title from a client is lost to a restart before the host stores it.
    var losesNextTitle = false
    /// Session lists wait until `releaseLists()`, answering with what the host had when asked.
    private var holdsLists = false
    private var heldLists: [CheckedContinuation<Void, Never>] = []

    init(configuring: Configuring = .grantsDecide) {
        self.configuring = configuring
    }

    @discardableResult
    func addTask(_ agentSessionID: String, titles: HostSessionTitles? = nil) async -> HostSessionID {
        let summary = HostSessionSummary(
            id: HostSessionID(), agentID: "fixture", agentName: "Fixture", agentSessionID: SessionID(agentSessionID),
            cwd: "/fixture/repo", phase: .idle, titles: titles)
        summaries.append(summary)
        await publish(summary)
        return summary.id
    }

    func titles(of agentSessionID: String) -> HostSessionTitles? {
        summaries.first { $0.agentSessionID == SessionID(agentSessionID) }?.titles
    }

    /// Changes a task's titles, as the host does while no client is attached, and tells whoever is.
    func setTitles(of agentSessionID: String, _ change: @Sendable (inout HostSessionTitles) -> Void) async {
        guard let index = summaries.firstIndex(where: { $0.agentSessionID == SessionID(agentSessionID) }) else {
            return
        }
        var titles = summaries[index].titles ?? HostSessionTitles()
        change(&titles)
        summaries[index].titles = titles
        await publish(summaries[index])
    }

    func connected(_ link: TitlesLink) {
        links.append(link)
    }

    /// Unreachable (this Mac asleep, the network gone) until `back()`.
    func drop() async {
        isDown = true
        let dropped = links
        links = []
        for link in dropped { await link.close() }
    }

    /// The process exits and launchd starts it again: a new epoch.
    func restart() async {
        await drop()
        epoch = UUID()
    }

    func back() {
        isDown = false
    }

    func holdLists() {
        holdsLists = true
    }

    var heldListCount: Int { heldLists.count }

    func setLosesNextTitle() {
        losesNextTitle = true
    }

    func releaseLists() {
        holdsLists = false
        for held in heldLists { held.resume() }
        heldLists = []
    }

    func list() async -> [HostSessionSummary] {
        let snapshot = summaries
        if holdsLists { await withCheckedContinuation { heldLists.append($0) } }
        return snapshot
    }

    /// `_native/session/set_title`, as the host applies it. False when it was lost to a restart.
    func setTitle(_ params: SetSessionTitleParams) async -> Bool {
        if params.source == .generated, losesNextTitle {
            losesNextTitle = false
            await restart()
            return false
        }
        guard let index = summaries.firstIndex(where: { $0.id == params.sessionID }) else { return true }
        var titles = summaries[index].titles ?? HostSessionTitles()
        switch params.source {
        case .user:
            let title = params.title?.trimmingCharacters(in: .whitespaces)
            titles.user = title?.isEmpty == false ? title : nil
        case .generated:
            guard titles.generated == nil, let title = params.title else { return true }
            titles.generated = title
            titles.fallback = nil
            titles.request = nil
        case .unknown:
            return true
        }
        summaries[index].titles = titles
        await publish(summaries[index])
        return true
    }

    private func publish(_ summary: HostSessionSummary) async {
        for link in links {
            await link.notify(HostProtocol.Method.sessionChanged, SessionChangedNotification(summary: summary))
        }
    }
}

/// One pairing's transport to a host, recording the title requests that came through it.
private actor TitlesLink: HostTransport {
    nonisolated var displayName: String { "Titles fixture" }
    let host: TitlesHost
    /// Whether the pairing may manage the host, which configuring titles needs.
    let managesHost: Bool
    private var peer: JSONRPCPeer?
    private(set) var calls: [String] = []
    private(set) var configurations: [ConfigureTitlesParams] = []
    private(set) var titlesSent: [SetSessionTitleParams] = []

    init(host: TitlesHost, managesHost: Bool) {
        self.host = host
        self.managesHost = managesHost
    }

    func generatedSent(for id: HostSessionID) -> Int {
        titlesSent.filter { $0.sessionID == id && $0.source == .generated }.count
    }

    func connect() async throws -> any ByteStream {
        while await host.isDown { try await Task.sleep(for: .milliseconds(10)) }
        let (clientEnd, hostEnd) = try UnixSocket.pair()
        let peer = JSONRPCPeer(channel: ByteChannel.socket(hostEnd, label: "titles-host"), label: "titles-host") {
            [weak self] event in
            if case .request(let message) = event {
                Task {
                    do { try await self?.receive(message) } catch {
                        print("FAIL: fixture request \(message.method): \(error)")
                        exit(1)
                    }
                }
            }
        }
        self.peer = peer
        peer.start()
        await host.connected(self)
        return ByteChannel.socket(clientEnd, label: "titles-client")
    }

    func close() {
        peer?.close()
        peer = nil
    }

    func notify(_ method: String, _ params: some Encodable & Sendable) {
        try? peer?.notify(method, params)
    }

    private func receive(_ message: JSONRPCPeer.Message) async throws {
        guard let id = message.id, let peer else { return }
        calls.append(message.method)
        switch message.method {
        case HostProtocol.Method.initialize:
            try peer.respond(
                to: id,
                with: HostInfo(
                    protocolVersion: HostProtocol.version, hostID: host.hostID, machineName: displayName,
                    hostInfo: PeerInfo(name: "Fixture", version: "1", build: "1"), epoch: await host.epoch,
                    processID: 1, startedAt: .now, channel: "tests"))
        case HostProtocol.Method.listAgents:
            let initialize: JSONValue = .object([
                "protocolVersion": .number(1), "agentCapabilities": .object(["loadSession": .bool(true)]),
            ])
            try peer.respond(
                to: id, with: [HostAgent(id: "fixture", name: "Fixture", state: .ready, initialize: initialize)])
        case HostProtocol.Method.listSessions:
            let summaries = await host.list()
            try? peer.respond(to: id, with: summaries)
        case HostProtocol.Method.configureTitles:
            configurations.append(try message.params(as: ConfigureTitlesParams.self))
            switch host.configuring {
            case .unknownMethod:
                try peer.respond(to: id, error: .methodNotFound(message.method))
            case .grantsDecide where !managesHost:
                try peer.respond(
                    to: id, error: RPCError(code: -32003, message: "Not allowed to change how this host titles tasks"))
            case .grantsDecide:
                try peer.respond(to: id, with: EmptyMessage())
            }
        case HostProtocol.Method.setSessionTitle:
            let params = try message.params(as: SetSessionTitleParams.self)
            titlesSent.append(params)
            // A title lost to a restart gets no answer: the connection closes under it.
            if await host.setTitle(params) { try? peer.respond(to: id, with: EmptyMessage()) }
        default:
            try peer.respond(to: id, error: .methodNotFound(message.method))
        }
    }
}

/// Writes titles on cue, counting what it was asked.
@MainActor
private final class FixtureTitler: SessionTitler {
    let hostProvider: HostTitleProvider? = .onDevice
    var answer = "Fix the login test"
    private(set) var prompts: [String] = []
    var isHeld = false

    func title(for request: TitleRequest) async throws -> String? {
        prompts.append(request.prompt)
        while isHeld { try await Task.sleep(for: .milliseconds(10)) }
        return answer
    }
}

/// How many times each client's connection finished `AppModel.hostConnected`.
@MainActor
private final class ConnectionLog {
    private var counts: [ObjectIdentifier: Int] = [:]

    func finished(_ client: NativeHostClient) { counts[ObjectIdentifier(client), default: 0] += 1 }
    func count(_ client: NativeHostClient) -> Int { counts[ObjectIdentifier(client), default: 0] }
}

private struct FixtureTitlesPlugin: NativePlugin {
    static let id = "titles-fixture"
    let manifest = PluginManifest(id: FixtureTitlesPlugin.id, name: "Titles fixture")
    let titler: (any SessionTitler)?
}

@main
@MainActor
private struct DroidRemoteTitlesRegression {
    static let titleKeys = ["sessionTitles.user", "sessionTitles.generated", "sessionTitles.fallback"]

    static func main() async {
        // The app's title store keeps to the standard defaults: start and end without any.
        for key in titleKeys { UserDefaults.standard.removeObject(forKey: key) }
        defer { for key in titleKeys { UserDefaults.standard.removeObject(forKey: key) } }
        do { try await run() } catch {
            print("FAIL: \(error)")
            exit(1)
        }
    }

    static func require(_ condition: Bool, _ message: String) throws {
        if !condition { throw TitlesFailure(message) }
    }

    static func wait(_ what: String, _ condition: () async -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(10)
        while !(await condition()) {
            guard ContinuousClock.now < deadline else { throw TitlesFailure("Timed out: \(what)") }
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    /// Long enough for anything already on its way to arrive, for checks that nothing does.
    static func settle() async throws {
        try await Task.sleep(for: .milliseconds(300))
    }

    static func run() async throws {
        try require(RemoteHosts.isEnabled, "Run with -NativeRemoteHosts YES")
        try require(
            UserDefaults.standard.object(forKey: HostTitles.defaultsKey) == nil && !HostTitles.isEnabled,
            "This Mac's own title switch must be unset")
        let scratch = FileManager.default.temporaryDirectory.appending(path: "remote-titles-\(UUID())")
        defer { try? FileManager.default.removeItem(at: scratch) }
        let defaults = PreviewUserDefaults()
        let manifest = PluginManifest(
            id: "fixture", name: "Fixture",
            agents: [AgentManifest(id: "fixture", name: "Fixture", command: "/usr/bin/true")])
        let titler = FixtureTitler()
        let plugins = PluginRegistry(
            builtIns: [ManifestPlugin(manifest: manifest), FixtureTitlesPlugin(titler: titler)], defaults: defaults)
        let app = AppModel(
            plugins: plugins, defaults: defaults, catalogURL: nil,
            hosts: RemoteHosts(store: FilePairedHostStore(directory: scratch.appending(path: "hosts"))))
        _ = app.runtimes.sync()
        // The app's wiring (AppModel.startRemoteHosts), without reaching for the network, counting
        // each client's finished connections.
        let connections = ConnectionLog()
        app.hosts.onEvent = { _, event in app.sessions.handle(event) }
        app.hosts.onRefreshed = { host in
            Task {
                await app.hostConnected(host)
                if let client = host.client { connections.finished(client) }
            }
        }
        let peerInfo = PeerInfo(name: "Fixture", version: "1", build: "1")
        func pair(_ host: TitlesHost, managesHost: Bool) async -> (RemoteHost, NativeHostClient, TitlesLink) {
            let link = TitlesLink(host: host, managesHost: managesHost)
            let client = NativeHostClient(transport: link, clientInfo: peerInfo)
            let paired = PairedHost(
                result: LinkPairingResult(
                    hostID: host.hostID, hostKey: host.hostKey, hostName: "Fixture", deviceID: UUID(),
                    grants: LinkGrants(manageHost: managesHost, runCommands: false), addresses: []),
                identity: LinkIdentity())
            let remote = app.hosts.add(paired)
            remote.start(using: client)
            return (remote, client, link)
        }
        func connected(_ client: NativeHostClient, times: Int = 1) async throws {
            try await wait("connection \(times)") { connections.count(client) >= times }
        }
        func key(_ session: String) -> SessionTitles.Key {
            SessionTitles.Key(agent: AgentDefinition.ID(rawValue: "fixture"), session: SessionID(session))
        }
        func shown(_ session: String) -> String? {
            app.titles.title(for: key(session), agentTitle: nil)
        }
        var clients: [NativeHostClient] = []

        // This Mac's own host: with its switch unset, the app titles and tells the host not to.
        let thisMac = TitlesHost()
        let thisMacLink = TitlesLink(host: thisMac, managesHost: true)
        let thisMacClient = NativeHostClient(transport: thisMacLink, clientInfo: peerInfo)
        clients.append(thisMacClient)
        await thisMacClient.start()
        _ = try await thisMacClient.connected()
        await HostTitlesWiring.connect(app, to: thisMacClient)
        try require(
            await thisMacLink.configurations == [ConfigureTitlesParams(provider: .off)],
            "This Mac's host wasn't left to the app as before")
        print("PASS: this Mac's host keeps today's default with its switch unset")

        // A paired host the pairing may manage is configured to title its tasks itself.
        let droid = TitlesHost()
        await droid.addTask("first")
        let (_, client, link) = await pair(droid, managesHost: true)
        clients.append(client)
        try await connected(client)
        let configured = await link.configurations
        try require(
            configured.map(\.provider) == [.onDevice],
            "The paired host was told \(configured.map(\.provider)) instead of titling its tasks")
        try require(app.titles.isTitledByHost(key("first")), "The app titles the paired host's task itself")
        print("PASS: the paired host titles its tasks with only NativeRemoteHosts on")

        // While this Mac is away: one task waits for a client (no model on the host), another got
        // its title from the host's own model.
        await droid.drop()
        await droid.setTitles(of: "first") {
            $0.fallback = "Fix the flaky login test"
            $0.request = HostTitleRequest(projectName: "repo", prompt: "fix the flaky login test", retry: 0)
        }
        await droid.addTask("second", titles: HostSessionTitles(generated: "Write the changelog"))
        titler.isHeld = true
        await droid.back()
        try await wait("the fallback after reconnecting") { shown("first") == "Fix the flaky login test" }
        try await wait("the host's own title after reconnecting") { shown("second") == "Write the changelog" }
        titler.isHeld = false
        try await wait("the requested title") { shown("first") == "Fix the login test" }
        try require(titler.prompts == ["fix the flaky login test"], "Titles written here: \(titler.prompts)")
        guard let first = await droid.summaries.first?.id else { throw TitlesFailure("No first task") }
        try require(await link.generatedSent(for: first) == 1, "The requested title wasn't sent once")
        try require(await droid.titles(of: "first")?.generated == "Fix the login test", "The host lacks the title")
        // Another reconnect adopts nothing new.
        await droid.drop()
        await droid.back()
        try await connected(client, times: 3)
        try await wait("configured again") { await link.configurations.count >= 3 }
        try await settle()
        try require(titler.prompts.count == 1, "Reconnecting wrote a title again")
        try require(await link.generatedSent(for: first) == 1, "Reconnecting sent a title again")
        print("PASS: titles written while away land once, and a client request is answered once")

        // A rename while away goes when the host is back, over the title it wrote meanwhile.
        await droid.drop()
        app.titles.rename(key("second"), to: "Changelog")
        await droid.back()
        try await wait("the rename to reach the host") { await droid.titles(of: "second")?.user == "Changelog" }
        try require(shown("second") == "Changelog", "The rename didn't win")
        // A rename while reconnecting wins over the host's older list.
        await droid.drop()
        await droid.holdLists()
        await droid.back()
        // Both the host's refresh and the titles' adoption wait on the host's list.
        try await wait("reconnecting") { await droid.heldListCount >= 2 }
        app.titles.rename(key("first"), to: "Login flake")
        try await wait("the rename during reconnect") { await droid.titles(of: "first")?.user == "Login flake" }
        await droid.releaseLists()
        try await settle()
        try require(await droid.titles(of: "first")?.user == "Login flake", "The host's older list undid the rename")
        try require(shown("first") == "Login flake", "The rename made during reconnect didn't win")
        print("PASS: renames made while away or while reconnecting win")

        // The host restarts while a title it asked for is on its way: written again once it's back.
        titler.answer = "Tidy the readme"
        titler.isHeld = true
        await droid.addTask(
            "third",
            titles: HostSessionTitles(
                fallback: "Tidy the readme please",
                request: HostTitleRequest(projectName: "repo", prompt: "tidy the readme please", retry: 0)))
        try await wait("the third title to be asked for") { titler.prompts.count == 2 }
        await droid.setLosesNextTitle()
        titler.isHeld = false
        try await wait("the lost title to be let go") {
            let isDown = await droid.isDown
            return isDown && app.titles.requestsForHosts[key("third")] == nil
        }
        await droid.back()
        try await wait("the title after the restart") {
            await droid.titles(of: "third")?.generated == "Tidy the readme"
        }
        try require(shown("third") == "Tidy the readme", "The title after the restart isn't shown")
        guard let third = await droid.summaries.first(where: { $0.agentSessionID == SessionID("third") })?.id else {
            throw TitlesFailure("No third task")
        }
        try require(await link.generatedSent(for: third) == 2, "The lost title wasn't sent again exactly once")
        print("PASS: a title cut off by a host restart is written again once it's back")

        // Paired again under the same host id: the new pairing follows, the old one hears nothing.
        let callsBefore = await link.calls.count
        let (_, newClient, newLink) = await pair(droid, managesHost: true)
        clients.append(newClient)
        try await connected(newClient)
        try require(await newLink.configurations.map(\.provider) == [.onDevice], "The new pairing wasn't configured")
        titler.answer = "Bump the version"
        await droid.addTask(
            "fourth",
            titles: HostSessionTitles(
                fallback: "Bump the version",
                request: HostTitleRequest(projectName: "repo", prompt: "bump the version", retry: 0)))
        try await wait("the fourth title") { await droid.titles(of: "fourth")?.generated == "Bump the version" }
        try await settle()
        try require(titler.prompts.filter { $0 == "bump the version" }.count == 1, "Two handlers wrote the title")
        try require(
            await newLink.titlesSent.count == 1, "The new pairing sent \(await newLink.titlesSent.count) titles")
        // Titles off in Settings reaches the host through the new pairing only, and back on again.
        plugins.setEnabled(false, for: FixtureTitlesPlugin.id)
        try await wait("titles off") { await newLink.configurations.last?.provider == .off }
        plugins.setEnabled(true, for: FixtureTitlesPlugin.id)
        try await wait("titles on") { await newLink.configurations.last?.provider == .onDevice }
        try await settle()
        try require(await link.calls.count == callsBefore, "The replaced pairing still got requests")
        print("PASS: pairing again follows once, and turning titles off and on reaches the host")

        // Pairings that can't configure their host leave it alone, and the app titles their tasks.
        let viewer = TitlesHost()
        await viewer.addTask("viewer")
        let (_, viewerClient, viewerLink) = await pair(viewer, managesHost: false)
        let older = TitlesHost(configuring: .unknownMethod)
        await older.addTask("older")
        let (_, olderClient, olderLink) = await pair(older, managesHost: true)
        clients += [viewerClient, olderClient]
        try await connected(viewerClient)
        try await connected(olderClient)
        await viewer.drop()
        await viewer.back()
        await older.drop()
        await older.back()
        try await connected(viewerClient, times: 2)
        try await connected(olderClient, times: 2)
        try require(await viewerLink.configurations.isEmpty, "A pairing without the grant tried to configure its host")
        try require(await olderLink.configurations.count == 1, "An older host was asked again after it couldn't")
        titler.answer = "Tidy the docs"
        for session in ["viewer", "older"] {
            try require(!app.titles.isTitledByHost(key(session)), "The app left \(session)'s task to its host")
            await app.titles.generateIfNeeded(
                for: key(session), request: TitleRequest(projectName: "repo", prompt: "tidy the docs"), using: titler)
            try require(shown(session) == "Tidy the docs", "The app didn't title \(session)'s task")
        }
        app.titles.rename(key("viewer"), to: "Docs")
        try await settle()
        try require(await viewerLink.titlesSent.isEmpty, "A pairing without the grant wrote titles to its host")
        try require(
            await thisMacLink.configurations == [ConfigureTitlesParams(provider: .off)],
            "This Mac's host heard about the paired hosts' titles")
        print("PASS: a pairing without the grant and an older host keep the app's own titles")

        // A host followed through a pairing that could manage it, paired again without the grant:
        // its task is the app's to title again, and nothing goes to either pairing.
        let demoted = TitlesHost()
        await demoted.addTask("demoted")
        let (_, managingClient, managingLink) = await pair(demoted, managesHost: true)
        clients.append(managingClient)
        try await connected(managingClient)
        try require(app.titles.isTitledByHost(key("demoted")), "The managing pairing didn't follow the task")
        let (_, restrictedClient, restrictedLink) = await pair(demoted, managesHost: false)
        clients.append(restrictedClient)
        try await connected(restrictedClient)
        try require(!app.titles.isTitledByHost(key("demoted")), "The task stayed with the replaced pairing")
        titler.answer = "Sort the imports"
        await app.titles.generateIfNeeded(
            for: key("demoted"), request: TitleRequest(projectName: "repo", prompt: "sort the imports"), using: titler)
        try require(shown("demoted") == "Sort the imports", "The app didn't title the task after the new pairing")
        app.titles.rename(key("demoted"), to: "Imports")
        try await settle()
        try require(shown("demoted") == "Imports", "The rename didn't hold")
        try require(await managingLink.titlesSent.isEmpty, "A title went to the replaced pairing")
        try require(await restrictedLink.titlesSent.isEmpty, "A title went to the pairing without the grant")
        try require(await restrictedLink.configurations.isEmpty, "The pairing without the grant configured its host")
        print("PASS: paired again without the grant, a followed host's task goes back to the app's titles")
        for client in clients { await client.stop() }
    }
}
