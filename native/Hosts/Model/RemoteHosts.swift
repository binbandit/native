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
/// of that name) turns them on.
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
    @ObservationIgnored var makeTaskWorkspaces: ((NativeHostClient, URL) -> any TaskWorkspaceProvider)?
    /// Every device's task workspaces, which `AppModel.taskWorkspaces` points at (it doesn't keep them).
    @ObservationIgnored var deviceWorkspaces: DeviceTaskWorkspaces?
    /// The hosts' clients the app has hooked its features to (titles), once each.
    @ObservationIgnored var wiredClients: Set<ObjectIdentifier> = []
    /// The app's definition of a host's agent (see `RemoteHost.definition`).
    @ObservationIgnored var definition: @MainActor (HostAgent) -> AgentDefinition = RemoteHost.definition(from:)
    @ObservationIgnored private let store: any PairedHostStore
    @ObservationIgnored private let discovery = RemoteHostDiscovery()
    @ObservationIgnored private var isStarted = false

    static let defaultsKey = "NativeRemoteHosts"
    private static let logger = Logger(subsystem: "Native", category: "RemoteHosts")

    /// Whether this run uses remote hosts at all.
    static var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: defaultsKey)
    }

    init(store: any PairedHostStore = FilePairedHostStore(directory: RemoteHosts.storeDirectory)) {
        self.store = store
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

    /// Reads the pairings and connects to every host. Once per run; nothing happens while the
    /// feature is off.
    func start() {
        guard Self.isEnabled, !isStarted else { return }
        isStarted = true
        do {
            all = try store.hosts().map(makeHost)
        } catch {
            problem = "Couldn't read paired hosts: \(error.localizedDescription)"
            Self.logger.error("Couldn't read paired hosts: \(error.localizedDescription, privacy: .public)")
        }
        discoverIfPaired()
        for host in all { host.start() }
        #if DEBUG
        if let link = RemoteHostsTesting.pairLink {
            Task { await pairForTesting(link) }
        }
        #endif
    }

    #if DEBUG
    /// Pairs with a `pair` link given at launch (`RemoteHostsTesting.pairLink`), with what the
    /// link offers, as Add Host would after the user chose Pair.
    private func pairForTesting(_ link: String) async {
        do {
            var invite = try PairingInvite(url: link)
            invite.addresses =
                RemoteHostsTesting.isLoopbackOnly
                ? invite.addresses.filter { $0.kind == .loopback } : invite.addresses
            var device = Self.deviceInfo
            device.requestedGrants = invite.grants
            let (paired, channel) = try await LinkPairing.pair(
                credential: .invite(invite), endpoints: LinkPairing.endpoints(for: invite, discovered: []),
                device: device, installationSecret: Self.installationSecret, log: { _ in },
                awaitingConfirmation: { _ in })
            channel.close()
            add(paired)
        } catch {
            problem = "Couldn't pair with the link given at launch: \(error.localizedDescription)"
            Self.logger.error("Test pairing failed: \(error.localizedDescription, privacy: .public)")
        }
    }
    #endif

    func stop() {
        for host in all { host.stop() }
        discovery.end()
    }

    /// Looks for paired hosts on the network only once there is one: browsing is what asks for
    /// local-network access, so a Mac that never pairs a host is never asked.
    private func discoverIfPaired() {
        guard !all.isEmpty, !RemoteHostsTesting.isLoopbackOnly else { return }
        discovery.begin()
    }

    // MARK: - What the user does

    /// Keeps a pairing Add Host made and connects to it. Pairing the same host instance again
    /// replaces its old pairing, keeping what the user called it.
    @discardableResult
    func add(_ paired: PairedHost) -> RemoteHost {
        var paired = paired
        if let existing = host(paired.hostID) {
            paired.label = paired.label ?? existing.paired.label
            existing.stop()
            all.removeAll { $0.id == paired.hostID }
        }
        save(paired)
        let host = makeHost(paired)
        all.append(host)
        if isStarted {
            discoverIfPaired()
            host.start()
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
        host.stop()
        do {
            try store.remove(id)
        } catch {
            problem = "Couldn't forget \(host.name): \(error.localizedDescription)"
        }
        return (host.paired, index)
    }

    /// Undoes `remove`.
    func restore(_ paired: PairedHost, at index: Int) {
        guard host(paired.hostID) == nil else { return }
        save(paired)
        let host = makeHost(paired)
        all.insert(host, at: min(index, all.count))
        if isStarted { host.start() }
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
        host.onEvent = { [weak self] host, event in self?.onEvent?(host, event) }
        host.onRefreshed = { [weak self] host in self?.onRefreshed?(host) }
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

/// The Bonjour browser paired hosts are found with, readable from the transports' own threads.
nonisolated final class RemoteHostDiscovery: Sendable {
    private let browser = Mutex<LinkBrowser?>(nil)

    func begin() {
        browser.withLock { browser in
            if browser == nil { browser = LinkBrowser() }
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
