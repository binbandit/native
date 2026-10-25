import Foundation
import NativeHostClient
import NativeHostProtocol
import NativeLink
import Observation
import Synchronization
import os

/// Every host this Mac is paired with, each with its own connection (`RemoteHost`), remembered
/// across launches with their names and pinned keys. Hosts are separate: removing one never touches
/// another, and nothing here reaches this Mac's own host (`DurableHost`).
///
/// Off by default until remote hosts work end to end: `-NativeRemoteHosts YES` (or the user default
/// of that name) turns them on, and the organization's policy can turn them off (`RemoteHostsPolicy`).
@Observable
final class RemoteHosts {
    /// In the order they were paired.
    private(set) var all: [RemoteHost] = []
    /// Reading or saving the pairings failed; the hosts page says so.
    private(set) var problem: String?

    /// Hears every remote host's events, in each host's order (AppModel+Hosts.swift routes them).
    @ObservationIgnored var onEvent: ((RemoteHost, NativeHostClient.Event) -> Void)?
    /// Told when a host's agents and sessions are listed after it connects (`RemoteHost.onRefreshed`).
    @ObservationIgnored var onRefreshed: ((RemoteHost) -> Void)?
    /// Makes a host's task workspaces: the Git feature's, on a store whose git runs on the host
    /// (`client`) and puts worktrees in the host's folder for them. Set by the app's wiring.
    @ObservationIgnored var makeTaskWorkspaces: ((RemoteHostID, NativeHostClient, URL) -> any TaskWorkspaceProvider)?
    /// Every device's task workspaces, which `AppModel.taskWorkspaces` points at (it doesn't keep them).
    @ObservationIgnored var deviceWorkspaces: DeviceTaskWorkspaces?
    /// The hosts' clients the app has hooked its features to (titles), once each.
    @ObservationIgnored var wiredClients: Set<ObjectIdentifier> = []
    /// Clients of pairings replaced or removed here, until the tasks still open on them move to
    /// their host's next client (AppModel+HostReconnection.swift).
    @ObservationIgnored private var retired: [RetiredClient] = []
    /// The app's definition of a host's agent (see `RemoteHost.definition`).
    @ObservationIgnored var definition: @MainActor (HostAgent) -> AgentDefinition = RemoteHost.definition(from:)
    /// Whether remote hosts are on, and the only way this model reaches them.
    @ObservationIgnored let policy: RemoteHostsPolicy
    @ObservationIgnored private let store: any PairedHostStore
    @ObservationIgnored private let discovery = RemoteHostDiscovery()
    @ObservationIgnored private var isStarted = false
    /// Connecting to the hosts and browsing for them: started, and on when the policy last said.
    @ObservationIgnored private var isActive = false
    @ObservationIgnored private var policyWatch: Task<Void, Never>?
    #if DEBUG
    @ObservationIgnored private var testPairing: Task<Void, Never>?
    #endif

    static let defaultsKey = "NativeRemoteHosts"
    private static let logger = Logger(subsystem: "Native", category: "RemoteHosts")

    /// Whether remote hosts are turned on for this run, before the organization has its say.
    static var isFeatureOn: Bool {
        UserDefaults.standard.bool(forKey: defaultsKey)
    }

    /// Whether this run uses remote hosts now: turned on, and allowed by the organization
    /// (`RemoteHostsPolicy.app`).
    static var isEnabled: Bool {
        RemoteHostsPolicy.app.isEnabled
    }

    /// The same, under this model's policy.
    var isEnabled: Bool {
        policy.isEnabled
    }

    init(
        store: any PairedHostStore = FilePairedHostStore(directory: RemoteHosts.storeDirectory),
        policy: RemoteHostsPolicy = .app
    ) {
        self.store = store
        self.policy = policy
    }

    /// `~/Library/Application Support/<bundle id>/Hosts`: one file per pairing, readable by the user alone.
    nonisolated static var storeDirectory: URL {
        URL.applicationSupportDirectory
            .appending(path: Bundle.main.bundleIdentifier ?? "Native", directoryHint: .isDirectory)
            .appending(path: "Hosts", directoryHint: .isDirectory)
    }

    func host(_ id: RemoteHostID) -> RemoteHost? {
        all.first { $0.id == id }
    }

    // MARK: - Lifecycle

    /// Reads the pairings and connects to every host, then follows the organization's policy for
    /// the rest of the run (`follow`). Once per run; nothing happens in a run with remote hosts off.
    func start() {
        guard policy.isOnForRun, !isStarted else { return }
        isStarted = true
        do {
            all = try store.hosts().map(makeHost)
        } catch {
            problem = "Couldn't read paired hosts: \(error.localizedDescription)"
            Self.logger.error("Couldn't read paired hosts: \(error.localizedDescription, privacy: .public)")
        }
        follow()
        policyWatch = Task { [weak self, policy] in
            for await _ in policy.changes {
                guard let self else { return }
                follow()
            }
        }
    }

    /// Connects or disconnects as the policy says now: on connects every pairing not connected yet,
    /// off stops all this client has under way with remote hosts (`disconnect`).
    private func follow() {
        if isEnabled {
            isActive = true
            discoverIfPaired()
            for host in all where host.client == nil { policy.connect(host) }
            #if DEBUG
            if testPairing == nil, let link = RemoteHostsTesting.pairLink {
                testPairing = Task { await pairForTesting(link) }
            }
            #endif
        } else if isActive {
            isActive = false
            disconnect()
        }
    }

    /// Stops browsing, every host's connection and its reconnecting, and the launch's test pairing.
    /// The pairings stay, and so do the agents and tasks on each host. Each host gets a new model,
    /// not started, so its open tasks move to the client it connects with next (`retire`).
    private func disconnect() {
        discovery.end()
        #if DEBUG
        testPairing?.cancel()
        #endif
        all = all.map { host in
            guard host.client != nil else { return host }
            retire(host)
            return makeHost(host.paired)
        }
    }

    #if DEBUG
    /// Pairs with a `pair` link given at launch (`RemoteHostsTesting.pairLink`), with what the
    /// link offers, as Add Host would after the user chose Pair. Once per run.
    private func pairForTesting(_ link: String) async {
        do {
            var invite = try PairingInvite(url: link)
            invite.addresses =
                RemoteHostsTesting.isLoopbackOnly
                ? invite.addresses.filter { $0.kind == .loopback } : invite.addresses
            var device = Self.deviceInfo
            device.requestedGrants = invite.grants
            let paired = try await policy.pair(invite, as: device, log: { _ in }, awaitingConfirmation: { _ in })
            try Task.checkCancellation()
            add(paired)
        } catch is CancellationError, is RemoteHostsPolicy.TurnedOff {
            Self.logger.info("Test pairing stopped: remote hosts are off")
        } catch {
            problem = "Couldn't pair with the link given at launch: \(error.localizedDescription)"
            Self.logger.error("Test pairing failed: \(error.localizedDescription, privacy: .public)")
        }
    }
    #endif

    /// Stops for good: every connection, browsing and following the policy.
    func stop() {
        policyWatch?.cancel()
        isActive = false
        for host in all { host.stop() }
        discovery.end()
    }

    /// Looks for paired hosts on the network only once there is one: browsing is what asks for
    /// local-network access, so a Mac that never pairs a host is never asked.
    private func discoverIfPaired() {
        guard !all.isEmpty, !RemoteHostsTesting.isLoopbackOnly, !discovery.isBrowsing,
            let browser = policy.browse()
        else { return }
        discovery.begin(browser)
    }

    // MARK: - What the user does

    /// Keeps a pairing Add Host made and connects to it while remote hosts are on; one kept while
    /// they're off connects when they're on again. Pairing the same host instance again replaces
    /// its old pairing, keeping what the user called it, and its open tasks move to the new client
    /// once it connects.
    @discardableResult
    func add(_ paired: PairedHost) -> RemoteHost {
        var paired = paired
        if let existing = host(paired.hostID) {
            paired.label = paired.label ?? existing.paired.label
            retire(existing)
            all.removeAll { $0.id == paired.hostID }
        }
        save(paired)
        let host = makeHost(paired)
        all.append(host)
        if isActive {
            discoverIfPaired()
            policy.connect(host)
        }
        return host
    }

    /// Names the host on this Mac; nil or blank goes back to its machine name.
    func rename(_ id: RemoteHostID, to name: String?) {
        guard let host = host(id) else { return }
        host.rename(to: name)
        save(host.paired)
    }

    /// Forgets the pairing here: the connection closes and this Mac's key for it is deleted. The
    /// host's sessions keep running there. Returns what `restore` needs to undo it.
    @discardableResult
    func remove(_ id: RemoteHostID) -> (paired: PairedHost, index: Int)? {
        guard let index = all.firstIndex(where: { $0.id == id }) else { return nil }
        let host = all.remove(at: index)
        retire(host)
        do {
            try store.remove(id)
        } catch {
            problem = "Couldn't forget \(host.name): \(error.localizedDescription)"
        }
        return (host.paired, index)
    }

    /// Undoes `remove`: the tasks still open here move to the new client once it connects.
    func restore(_ paired: PairedHost, at index: Int) {
        guard host(paired.hostID) == nil else { return }
        save(paired)
        let host = makeHost(paired)
        all.insert(host, at: min(index, all.count))
        if isActive { policy.connect(host) }
    }

    // MARK: - Pairings that ended here

    /// A client of a pairing replaced or removed here, and what its tasks need to move on.
    struct RetiredClient {
        let host: RemoteHostID
        /// The key its pairing pinned: only a client pinning the same one takes its tasks over.
        let hostKey: LinkPublicKey
        let client: NativeHostClient
        /// The host process each of its sessions' transcripts comes from (`RemoteHost.deliveredRuns`).
        let runs: [HostSessionID: UUID]
    }

    /// Stops a host's client for good, keeping it for the host's next client to take its tasks from.
    /// A pairing the host ended has no client any more, so its tasks never move by themselves.
    private func retire(_ host: RemoteHost) {
        if let client = host.client {
            // Nothing is hooked to it any more, and a later client may reuse its identifier.
            wiredClients.remove(ObjectIdentifier(client))
            retired.append(
                RetiredClient(host: host.id, hostKey: host.paired.hostKey, client: client, runs: host.deliveredRuns))
        }
        host.stop()
    }

    /// The retired clients whose tasks `host` may take over: the same host, pinning the same key.
    /// Another key, even under the same id, might be another machine.
    func retiredClients(of host: RemoteHost) -> [RetiredClient] {
        retired.filter { $0.host == host.id && $0.hostKey == host.paired.hostKey }
    }

    /// Forgets retired clients whose tasks have moved on.
    func forget(_ clients: [RetiredClient]) {
        retired.removeAll { old in clients.contains { $0.client === old.client } }
    }

    private func save(_ paired: PairedHost) {
        do {
            try store.save(paired)
        } catch {
            problem = "Couldn't save the pairing with \(paired.displayName): \(error.localizedDescription)"
            Self.logger.error("Couldn't save a pairing: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func makeHost(_ paired: PairedHost) -> RemoteHost {
        let discovery = discovery
        let host = RemoteHost(
            paired: paired, discovered: { discovery.current }, addresses: RemoteHostsTesting.addresses)
        host.definition = { [weak self] agent in self?.definition(agent) ?? RemoteHost.definition(from: agent) }
        // A replaced or removed pairing's client can still hand over what it read before it stopped.
        host.onEvent = { [weak self] host, event in
            guard let self, self.host(host.id) === host else { return }
            onEvent?(host, event)
        }
        host.onRefreshed = { [weak self] host in
            guard let self, self.host(host.id) === host else { return }
            onRefreshed?(host)
        }
        return host
    }

    // MARK: - This Mac, as hosts see it

    /// How this Mac introduces itself when it pairs and connects.
    static var deviceInfo: LinkDeviceInfo {
        LinkDeviceInfo(name: PlatformDevice.name, model: PlatformDevice.model, system: PlatformDevice.system)
    }

    static var peerInfo: PeerInfo {
        let info = Bundle.main.infoDictionary ?? [:]
        return PeerInfo(
            name: PlatformDevice.name, version: info["CFBundleShortVersionString"] as? String ?? "0",
            build: info["CFBundleVersion"] as? String ?? "0")
    }

    /// A random secret for this installation. Hosts only ever see a hash of it with their own key
    /// (`LinkDeviceInfo.installationTag`), so pairing again replaces the old entry on that host
    /// without letting two hosts link this Mac. Pass it to `LinkPairing.pair`.
    static var installationSecret: Data {
        let key = "RemoteHostsInstallationSecret"
        if let data = UserDefaults.standard.data(forKey: key), data.count == 32 { return data }
        var generator = SystemRandomNumberGenerator()
        let data = Data((0..<32).map { _ in UInt8.random(in: .min ... .max, using: &generator) })
        UserDefaults.standard.set(data, forKey: key)
        return data
    }
}

/// A Bonjour browser for Native hosts on the local network (`LinkBrowser`).
nonisolated protocol RemoteHostBrowsing: Sendable {
    /// What it sees right now.
    var current: [DiscoveredHost] { get }
    func cancel()
}

nonisolated extension LinkBrowser: RemoteHostBrowsing {}

/// The Bonjour browser paired hosts are found with, readable from the transports' own threads.
nonisolated final class RemoteHostDiscovery: Sendable {
    private let browser = Mutex<(any RemoteHostBrowsing)?>(nil)

    var isBrowsing: Bool {
        browser.withLock { $0 != nil }
    }

    /// Finds hosts with `new` until `end()`.
    func begin(_ new: any RemoteHostBrowsing) {
        browser.withLock { browser in
            browser?.cancel()
            browser = new
        }
    }

    func end() {
        browser.withLock { browser in
            browser?.cancel()
            browser = nil
        }
    }

    var current: [DiscoveredHost] {
        browser.withLock { $0?.current ?? [] }
    }
}

/// Launch arguments for testing against a second host on this Mac (`docs/durability.md`, "Host
/// identity and many hosts"). Off by default, and only in development builds.
enum RemoteHostsTesting {
    /// `-NativeRemoteHostsLoopbackOnly YES`: reach hosts only at their loopback address, with no
    /// Bonjour, so a stand-in host on this Mac is reached without local-network permission.
    static var isLoopbackOnly: Bool {
        #if DEBUG
        UserDefaults.standard.bool(forKey: "NativeRemoteHostsLoopbackOnly")
        #else
        false
        #endif
    }

    /// `-NativeRemoteHostsPairLink <link>`: pairs with a host's `pair` link at launch, for testing
    /// against a stand-in host before Add Host is in the window.
    static var pairLink: String? {
        #if DEBUG
        UserDefaults.standard.string(forKey: "NativeRemoteHostsPairLink")
        #else
        nil
        #endif
    }

    /// The addresses to try for a pairing.
    static func addresses(_ paired: PairedHost) -> [LinkAddress] {
        isLoopbackOnly ? paired.addresses.filter { $0.kind == .loopback } : paired.addresses
    }
}
