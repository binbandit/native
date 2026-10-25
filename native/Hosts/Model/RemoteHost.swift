import ACP
import Foundation
import Git
import NativeHostClient
import NativeHostProtocol
import NativeLink
import Observation
import os

/// One paired host this Mac runs sessions on (a Mac mini in a closet, a second Native): its own
/// connection over NativeLink, the agents it runs and the sessions it holds, and a connection log.
/// Nothing here is shared with another host; unpairing one never touches another.
///
/// The client lives as long as the pairing: it reconnects by itself across drops, sleeps and host
/// restarts, and the session models made on it keep working through all of them. It stops only
/// when the host is removed here, or when the host says the pairing is over. Pairing the host
/// again, or undoing its removal, makes a new one, and the open tasks move to its client
/// (AppModel+HostReconnection.swift).
@Observable
final class RemoteHost: Identifiable {
    let id: RemoteHostID
    /// The pairing: the host's pinned key, its addresses and this Mac's key for it alone.
    private(set) var paired: PairedHost
    private(set) var phase = PairedHostPhase.connecting
    /// The host's agents as runtimes, with their status, capabilities and sign-in methods, kept
    /// current from its events: the same `AgentRuntimeStatus` every other agent row shows.
    private(set) var runtimes: [AgentRuntime] = []
    /// Every session the host has open (the user's, tasks and subagents), kept current.
    private(set) var sessions: [HostSessionSummary] = []
    /// Each step of connecting, newest last, for the host's page.
    private(set) var log: [LinkLogEntry] = []
    /// When this Mac last had a connection, for "Last connected 3h ago" while it's offline.
    private(set) var lastConnected: Date?
    /// What the host's agents did while this Mac was away from it (closed, asleep, off the
    /// network), from its activity journal, until dismissed.
    var away: AwaySummary?
    /// The user's sessions each agent saved in each of this host's checkouts (`session/list` by
    /// folder), for the sidebar beside the ones the host has open.
    private(set) var history: [String: [RemoteListedSession]] = [:]
    /// Where the host makes task worktrees (`HostProjectList.worktreesFolder`), once it has said.
    var worktreesFolder: String?
    /// Each checkout's repository name as the host's git reads it, by the checkout's folder.
    private(set) var repositoryNames: [String: String] = [:]
    /// How the host's machine is doing (system, model, uptime, load, keep-awake), as it last said:
    /// read on each connection, then pushed about every 30 seconds while connected.
    private(set) var status: HostStatus?

    /// Nil until `start()`, and again after `stop()`.
    @ObservationIgnored private(set) var client: NativeHostClient?
    /// Its tasks' worktrees, made and put away with git on the host (`RemoteHosts.makeTaskWorkspaces`),
    /// once the host has said where they go.
    @ObservationIgnored var taskWorkspaces: (any TaskWorkspaceProvider)?
    /// Hears every event the host sends, in order, before the answers to requests made after them
    /// (the app routes session events to its models with it). Set before `start()`.
    @ObservationIgnored var onEvent: ((RemoteHost, NativeHostClient.Event) -> Void)?
    /// Told once the host's agents and sessions are listed after each connection, so the app can
    /// list its checkouts' history and open what's working (AppModel+HostsSessions.swift).
    @ObservationIgnored var onRefreshed: ((RemoteHost) -> Void)?
    /// The app's definition of one of the host's agents: its plugin's when this Mac has the same
    /// agent, so names and icons match; else one made from what the host says.
    @ObservationIgnored var definition: @MainActor (HostAgent) -> AgentDefinition = RemoteHost.definition(from:)
    @ObservationIgnored private let discovered: @Sendable () -> [DiscoveredHost]
    @ObservationIgnored private let addresses: (PairedHost) -> [LinkAddress]
    /// The host process this run last connected to: the first connection of a run reads what
    /// happened while away; later ones to the same process only catch up.
    @ObservationIgnored private var lastEpoch: UUID?
    /// The host process (its epoch) each session's events came from, as this client last passed
    /// them on: what a new pairing's client compares with to tell what the app has already.
    @ObservationIgnored private var eventRuns: [HostSessionID: UUID] = [:]
    /// Sessions this client took over from an earlier pairing's client (`skipDelivered`), with the
    /// last event the app has of each: the replay attaching them starts with is held back up to it.
    @ObservationIgnored private var delivered: [HostSessionID: HostEventMark] = [:]

    static let logLimit = 200
    private static let logger = Logger(subsystem: "Native", category: "RemoteHosts")

    init(
        paired: PairedHost, discovered: @escaping @Sendable () -> [DiscoveredHost] = { [] },
        addresses: @escaping (PairedHost) -> [LinkAddress] = { $0.addresses }
    ) {
        id = paired.hostID
        self.paired = paired
        self.discovered = discovered
        self.addresses = addresses
    }

    /// What the user calls it here; the host's machine name until they rename it.
    var name: String {
        paired.displayName
    }

    var isOnline: Bool {
        phase.isConnected
    }

    /// The host's own build, channel and machine name, while connected.
    var info: HostInfo? {
        phase.hostInfo
    }

    func runtime(_ agent: AgentDefinition.ID) -> AgentRuntime? {
        runtimes.first { $0.agent.id == agent }
    }

    func session(_ id: HostSessionID) -> HostSessionSummary? {
        sessions.first { $0.id == id }
    }

    /// Where the host keeps the task worktrees of the checkout at `checkout`: a folder per
    /// repository in its worktrees folder, named as the Git feature names it (`GitStore.taskLocation`):
    /// after the repository, which for a linked checkout is its main checkout's name, as the host's
    /// git read it (`repositoryNames`), else the checkout's own folder name until it has.
    func taskLocation(ofCheckoutAt checkout: String) -> String? {
        worktreesFolder.map { folder in
            let name = repositoryNames[checkout] ?? URL(filePath: checkout).lastPathComponent
            return URL(filePath: folder, directoryHint: .isDirectory)
                .appending(path: Worktree.slug(name, maxLength: 60))
                .path(percentEncoded: false)
        }
    }

    /// Notes the repository name the host's git gives the checkout at `checkout` (`Repository.name`).
    func noteRepositoryName(_ name: String, ofCheckoutAt checkout: String) {
        if repositoryNames[checkout] != name { repositoryNames[checkout] = name }
    }

    /// Whether a session in `cwd` works in the checkout at `checkout`: in it, or in one of its task
    /// worktrees. Compared as the host spells paths, never resolved on this Mac's disk (`plain`).
    func isTaskFolder(_ cwd: String, ofCheckoutAt checkout: String) -> Bool {
        let cwd = Self.plain(cwd)
        if cwd == Self.plain(checkout) { return true }
        guard let location = taskLocation(ofCheckoutAt: checkout).map(Self.plain) else { return false }
        return cwd.hasPrefix(location + "/")
    }

    /// A path on the host as this Mac compares it: without a trailing slash, and without the
    /// `/private` macOS puts before `/tmp`, `/var` and `/etc`, since a host reports either spelling.
    nonisolated static func plain(_ path: String) -> String {
        var path = path
        while path.count > 1, path.hasSuffix("/") { path.removeLast() }
        for linked in ["/tmp", "/var", "/etc"]
        where path == "/private" + linked || path.hasPrefix("/private" + linked + "/") {
            path.removeFirst("/private".count)
        }
        return path
    }

    // MARK: - Connection

    /// Connects, and keeps reconnecting until `stop()` or the host says the pairing ended.
    func start() {
        guard client == nil, !isPairingEnded else { return }
        phase = .connecting
        record(LinkLogEntry(.info, "Connecting to \(paired.machineName)"))
        var reachable = paired
        reachable.addresses = addresses(paired)
        let transport = PairedHostTransport(
            host: reachable, device: RemoteHosts.deviceInfo, discovered: discovered,
            log: { [weak self] entry in Task { @MainActor in self?.record(entry) } },
            pairingEnded: { [weak self] error in Task { @MainActor in self?.pairingEnded(error) } })
        let client = NativeHostClient(transport: transport, clientInfo: RemoteHosts.peerInfo)
        start(using: client)
    }

    /// Accepts a configured link so model checks can exercise the same routing over an isolated transport.
    func start(using client: NativeHostClient) {
        guard self.client == nil, !isPairingEnded else { return }
        self.client = client
        let receive: NativeHostClient.EventHandler = { [weak self] event in await self?.receive(event) }
        let receiveStatus: @Sendable (HostStatus) async -> Void = { [weak self] status in
            await self?.receive(status)
        }
        Task {
            await client.addEventHandler(receive)
            await client.addStatusHandler(receiveStatus)
            await client.start()
        }
    }

    /// Stops for good: the host was removed here. Its sessions keep running on the host.
    func stop() {
        guard let client else { return }
        self.client = nil
        Task { await client.stop() }
    }

    private var isPairingEnded: Bool {
        if case .pairingEnded = phase { true } else { false }
    }

    /// The user renamed it on this Mac; the host keeps its own machine name.
    func rename(to label: String?) {
        let trimmed = label?.trimmingCharacters(in: .whitespacesAndNewlines)
        paired.label = trimmed?.isEmpty == false && trimmed != paired.machineName ? trimmed : nil
    }

    /// The host revoked or forgot this Mac, or couldn't prove its pinned key, as the transport
    /// reports. The client goes for good, so its tasks never move to a new pairing by themselves.
    func pairingEnded(_ error: LinkError) {
        record(LinkLogEntry(.failure, error.localizedDescription))
        phase = .pairingEnded(error)
        stop()
    }

    private func record(_ entry: LinkLogEntry) {
        log.append(entry)
        if log.count > Self.logLimit { log.removeFirst(log.count - Self.logLimit) }
    }

    private func receive(_ event: NativeHostClient.Event) {
        switch event {
        case .connection(let state):
            guard !isPairingEnded else { return }
            phase = PairedHostPhase(state)
            if case .connected(let info) = state {
                lastConnected = .now
                if paired.machineName != info.machineName { paired.machineName = info.machineName }
                let isFirst = lastEpoch == nil
                lastEpoch = info.epoch
                // Handlers mustn't wait on requests to the client that called them.
                Task {
                    await refresh()
                    onRefreshed?(self)
                    await readActivity(host: info, summarize: isFirst)
                }
            }
        case .activity(let entry):
            // Seen as it happened, so it isn't news next time.
            HostSeenActivity.remember(entry.id, on: id)
        case .agentChanged(let agent):
            apply(agent)
        case .sessionChanged(let summary):
            if let index = sessions.firstIndex(where: { $0.id == summary.id }) {
                sessions[index] = summary
            } else {
                sessions.append(summary)
            }
        case .sessionClosed(let id):
            sessions.removeAll { $0.id == id }
            eventRuns[id] = nil
            delivered[id] = nil
        case .sessionEvent(let id, let step):
            guard isNews(step, of: id) else { return }
        default:
            break
        }
        onEvent?(self, event)
    }

    /// Whether the app hasn't seen a session's event: not one it had through an earlier pairing's
    /// client from the same host process. Events of another process are all news: it numbers them
    /// afresh, from a reset.
    private func isNews(_ step: SessionMirror.Step, of id: HostSessionID) -> Bool {
        if let mark = delivered[id] {
            if mark.run == lastEpoch, step.event.seq <= mark.seq { return false }
            delivered[id] = nil
        }
        if let lastEpoch { eventRuns[id] = lastEpoch }
        return true
    }

    /// Takes over a session from an earlier pairing's client, whose transcript here is folded up
    /// to `mark`: the replay this client attaches it with passes on only what comes after.
    func skipDelivered(_ id: HostSessionID, through mark: HostEventMark) {
        delivered[id] = mark
    }

    /// The host process each session's transcript here comes from, through this client: for the
    /// client of the next pairing (`RemoteHosts.RetiredClient`).
    var deliveredRuns: [HostSessionID: UUID] {
        eventRuns.merging(delivered.mapValues(\.run)) { _, pending in pending }
    }

    private func receive(_ status: HostStatus) {
        if self.status != status { self.status = status }
    }

    /// The host's agents and sessions after (re)connecting.
    func refresh() async {
        guard let client else { return }
        do {
            async let agents = client.agents()
            async let sessions = client.sessions()
            let (listedAgents, listedSessions) = try await (agents, sessions)
            for agent in listedAgents { apply(agent) }
            runtimes.removeAll { runtime in !listedAgents.contains { $0.id == runtime.agent.id.rawValue } }
            self.sessions = listedSessions
            // A host from before machine status answers without it.
            if let status = try? await client.hostStatus() { receive(status) }
        } catch {
            record(LinkLogEntry(.failure, "Couldn't list agents and tasks: \(error.localizedDescription)"))
        }
    }

    /// Reads the journal since the last entry this app saw on the host; on the run's first
    /// connection, sums it up as "while you were away".
    private func readActivity(host info: HostInfo, summarize: Bool) async {
        guard let client else { return }
        let seen = HostSeenActivity.lastSeen(on: info.hostID)
        do {
            let entries = try await HostSeenActivity.entries(after: seen, from: client)
            HostSeenActivity.remember(entries, after: seen, on: info.hostID)
            if summarize, seen != nil,
                HostNotificationsSwitch.history.usesActivitySummary(
                    on: info, enabled: HostNotificationsSwitch.isEnabled)
            {
                away = AwaySummary(entries: entries, sessions: sessions)
            }
        } catch {
            record(LinkLogEntry(.failure, "Couldn't read what happened meanwhile: \(error.localizedDescription)"))
        }
    }

    func dismissAway() {
        away = nil
    }

    /// Takes a task off the summary once the user opened it; the summary goes when it's empty.
    func removeAwayItem(_ id: HostSessionID) {
        away?.items.removeAll { $0.id == id }
        if away?.items.isEmpty == true { away = nil }
    }

    /// Lists each agent's saved sessions in `folders` (this host's checkouts of the user's
    /// projects), for the sidebar. Agents that can't run there are skipped; the rest start if they
    /// need to, as listing does on this Mac.
    func refreshHistory(in folders: [String]) async {
        guard let client, isOnline else { return }
        for folder in Set(folders) {
            var listed: [RemoteListedSession] = []
            for runtime in runtimes where runtime.isAvailable {
                let agent = runtime.agent.id
                do {
                    let response = try await client.listAgentSessions(
                        ListAgentSessionsParams(agentID: agent.rawValue, cwd: folder))
                    listed += response.sessions.map { RemoteListedSession(agent: agent, info: $0) }
                } catch {
                    record(
                        LinkLogEntry(
                            .failure,
                            "\(runtime.agent.displayName) couldn't list \(folder): \(error.localizedDescription)"))
                }
            }
            history[folder] = listed
        }
    }

    private func apply(_ agent: HostAgent) {
        guard let client else { return }
        if let runtime = runtime(AgentDefinition.ID(rawValue: agent.id)) {
            runtime.apply(agent)
        } else {
            let runtime = AgentRuntime(agent: definition(agent), host: client)
            runtime.apply(agent)
            runtimes.append(runtime)
        }
    }

    /// An agent this Mac has no plugin for: named as the host names it.
    static func definition(from agent: HostAgent) -> AgentDefinition {
        AgentDefinition(
            AgentManifest(id: agent.id, name: agent.name, command: agent.launchedSpec?.command ?? agent.id),
            pluginID: "host")
    }

    // MARK: - Agents

    /// Starts an agent on the host and waits until it's ready or failed; its runtime says how.
    func startAgent(_ agent: AgentDefinition.ID) async {
        guard let runtime = runtime(agent) else { return }
        await runtime.startOnHost()
    }

    /// Signs an agent in on the host with one of the methods it offers (`AgentRuntime.authMethods`).
    /// The agent runs the method on the host: one that opens a browser opens it there, not here, so
    /// a host without a screen needs a method that doesn't (an API key, a device code).
    func signIn(_ agent: AgentDefinition.ID, with method: AuthMethod) async throws {
        guard let runtime = runtime(agent) else { throw NativeHostClient.Failure.notConnected }
        try await runtime.signIn(with: method)
    }

    /// Signs an agent in on the host with a key or token, for a method that takes one
    /// (`AuthMethod.takesSecret`). It goes over the encrypted link to the host, which keeps it in
    /// its keychain and never sends it back (`AgentRuntime.savedCredentials` says it's there).
    /// Needs a pairing that may manage the host.
    func signIn(_ agent: AgentDefinition.ID, with method: AuthMethod, apiKey: String) async throws {
        guard let client, let runtime = runtime(agent) else { throw NativeHostClient.Failure.notConnected }
        runtime.apply(try await client.setAgentCredential(agent.rawValue, methodID: method.id, secret: apiKey))
    }

    /// Forgets the key saved on the host for `method`, and stops the agent using it.
    func removeAPIKey(_ agent: AgentDefinition.ID, for method: AuthMethod) async throws {
        guard let client, let runtime = runtime(agent) else { throw NativeHostClient.Failure.notConnected }
        runtime.apply(try await client.removeAgentCredential(agent.rawValue, methodID: method.id))
    }

    /// Restarts the agent and asks again whether it's signed in, after the user signed in on the
    /// host some other way (over SSH). Fails with the host's `busy` while it's working.
    func checkSignIn(_ agent: AgentDefinition.ID) async throws {
        guard let client, let runtime = runtime(agent) else { throw NativeHostClient.Failure.notConnected }
        runtime.apply(try await client.checkAgentSignIn(agent.rawValue))
    }

    /// Ends a sign-in waiting on the user (`AgentRuntime.signInLink`); `signIn(_:with:)` then fails.
    func cancelSignIn(_ agent: AgentDefinition.ID) async throws {
        guard let client, let runtime = runtime(agent) else { throw NativeHostClient.Failure.notConnected }
        runtime.apply(try await client.cancelAgentSignIn(agent.rawValue))
    }
}

/// The last of a session's events the app has: its sequence number, in the host process (epoch)
/// that numbered it.
struct HostEventMark: Hashable {
    let run: UUID
    let seq: Int
}

/// A session an agent on a paired host saved in one of its checkouts.
struct RemoteListedSession: Hashable {
    let agent: AgentDefinition.ID
    let info: SessionInfo

    var key: SessionKey {
        SessionKey(agent: agent, id: info.sessionId)
    }
}
