import ACP
import Foundation
import NativeHostClient
import NativeHostProtocol
import NativePolicy
import Synchronization

@testable import Native
@testable import NativeLink

// The organization's `policy.remoteHosts.enabled` against this client's outbound remote-host work:
// discovery, connections and reconnecting, pairing by link and over SSH, and the launch's test
// pairing. The checks count what was attempted through recording fakes, not what a view shows.
//
// `-check repro` uses the app's own policy and network code, so it also runs on a build without the
// fix (`--before`): its launch arguments simulate the organization's policy. `-check matrix` changes
// in-memory policies during the run.

private struct PolicyFailure: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

/// What reached out, by operation, from whichever thread did.
private final class Reached: Sendable {
    private let counts = Mutex<[String: Int]>([:])

    func note(_ operation: String) {
        counts.withLock { $0[operation, default: 0] += 1 }
    }

    func count(_ operation: String) -> Int {
        counts.withLock { $0[operation] ?? 0 }
    }

    /// Every try at reaching a host: connecting, browsing, pairing by link or over SSH.
    var attempts: Int {
        ["connect", "browse", "pair", "ssh"].map(count).reduce(0, +)
    }
}

/// The organization's `policy.remoteHosts.enabled`, in memory; nil leaves it unmanaged. Setting it
/// posts what a changed managed preference posts, so a `PolicyCenter` following it updates.
private final class ScratchPolicy: PolicySource, Sendable {
    private let value: Mutex<Bool?>
    private let organizationName: String?
    private let organizationContact: String?

    init(_ value: Bool?, organizationName: String? = nil, organizationContact: String? = nil) {
        self.value = Mutex(value)
        self.organizationName = organizationName
        self.organizationContact = organizationContact
    }

    func set(_ value: Bool?) {
        self.value.withLock { $0 = value }
        NotificationCenter.default.post(name: UserDefaults.didChangeNotification, object: nil)
    }

    func managedEntry(forKey key: String) -> ManagedEntry {
        if key == PolicyKey.organizationName.rawValue {
            return organizationName.map(ManagedEntry.value) ?? .absent
        }
        if key == PolicyKey.organizationContact.rawValue {
            return organizationContact.map(ManagedEntry.value) ?? .absent
        }
        guard key == PolicyKey.remoteHostsEnabled.rawValue else { return .absent }
        return value.withLock { $0 }.map(ManagedEntry.value) ?? .absent
    }

    func userValue(forKey key: String) -> Any? { nil }

    var managedKeys: [String]? {
        (value.withLock { $0 } == nil ? [] : [PolicyKey.remoteHostsEnabled.rawValue])
            + (organizationName == nil ? [] : [PolicyKey.organizationName.rawValue])
            + (organizationContact == nil ? [] : [PolicyKey.organizationContact.rawValue])
    }
}

/// One host process: a task and its event log, shared by every connection to it.
private actor FixtureHost {
    let hostID = HostID()
    let hostKey = LinkIdentity().publicKey
    let epoch = UUID()
    let session: HostSessionID
    let summary: HostSessionSummary
    private(set) var log: [HostEvent] = []
    private var subscribers: [FixtureLink] = []

    init() {
        let session = HostSessionID()
        self.session = session
        summary = HostSessionSummary(
            id: session, agentID: "fixture", agentName: "Fixture", agentSessionID: SessionID("task"),
            cwd: "/fixture/repo", title: "Fixture task", phase: .idle)
    }

    func log(_ payload: HostEvent.Payload) async {
        let event = HostEvent(seq: (log.last?.seq ?? 0) + 1, payload: payload)
        log.append(event)
        for link in subscribers { await link.send(event) }
    }

    /// Subscribes `link` and returns what it hasn't seen, in one step, as the real host does.
    func attach(_ link: FixtureLink, after seq: Int?, epoch: UUID?) -> [HostEvent] {
        subscribers.removeAll { $0 === link }
        subscribers.append(link)
        guard epoch == self.epoch, let seq else { return log }
        return log.filter { $0.seq > seq }
    }
}

/// One client's transport to the host, recording each connection and the requests on it.
private actor FixtureLink: HostTransport {
    enum Answer {
        /// Connects and answers as a host does.
        case serve
        /// Nothing answers: each try fails at once and the client keeps trying.
        case unreachable
        /// The connection takes until it's cancelled, as the network's does.
        case hold
    }

    nonisolated var displayName: String { "Policy fixture" }
    let host: FixtureHost
    let reached: Reached
    let answer: Answer
    private var peer: JSONRPCPeer?
    private(set) var calls: [String] = []

    init(host: FixtureHost, reached: Reached, answer: Answer) {
        self.host = host
        self.reached = reached
        self.answer = answer
    }

    func connect() async throws -> any ByteStream {
        reached.note("connect")
        switch answer {
        case .serve:
            break
        case .unreachable:
            throw PolicyFailure("Nothing answered")
        case .hold:
            do {
                try await Task.sleep(for: .seconds(60))
            } catch {
                reached.note("connectCancelled")
                throw error
            }
            throw PolicyFailure("A held connection was never cancelled")
        }
        let (clientEnd, hostEnd) = try UnixSocket.pair()
        let peer = JSONRPCPeer(channel: ByteChannel.socket(hostEnd, label: "policy-host"), label: "policy-host") {
            [weak self] event in
            if case .request(let message) = event {
                Task { try? await self?.receive(message) }
            }
        }
        self.peer = peer
        peer.start()
        Task { [reached] in
            await peer.closed()
            reached.note("closed")
        }
        return ByteChannel.socket(clientEnd, label: "policy-client")
    }

    func send(_ event: HostEvent) {
        try? peer?.notify(
            HostProtocol.Method.sessionEvent, SessionEventNotification(sessionID: host.session, event: event))
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
                    hostInfo: PeerInfo(name: "Fixture", version: "1", build: "1"), epoch: host.epoch,
                    processID: 1, startedAt: .now, channel: "tests"))
        case HostProtocol.Method.listAgents:
            let initialize: JSONValue = .object([
                "protocolVersion": .number(1), "agentCapabilities": .object(["loadSession": .bool(true)]),
            ])
            try peer.respond(
                to: id, with: [HostAgent(id: "fixture", name: "Fixture", state: .ready, initialize: initialize)])
        case HostProtocol.Method.listSessions:
            try peer.respond(to: id, with: [host.summary])
        case HostProtocol.Method.openSession:
            for event in await host.attach(self, after: nil, epoch: nil) { send(event) }
            try peer.respond(to: id, with: host.summary)
        case HostProtocol.Method.attach:
            let params = try message.params(as: AttachParams.self)
            for event in await host.attach(self, after: params.afterSeq, epoch: params.epoch) { send(event) }
            try peer.respond(to: id, with: AttachResult(summary: host.summary))
        case HostProtocol.Method.configureTitles, HostProtocol.Method.detach:
            try peer.respond(to: id, with: EmptyMessage())
        default:
            try peer.respond(to: id, error: .methodNotFound(message.method))
        }
    }
}

#if !BEFORE
/// A Bonjour browser that only records that it browsed.
private final class FixtureBrowser: RemoteHostBrowsing {
    let reached: Reached

    init(_ reached: Reached) {
        self.reached = reached
        reached.note("browse")
    }

    var current: [DiscoveredHost] { [] }

    func cancel() {
        reached.note("browseStopped")
    }
}
#endif

/// Holds pairings by link until released, past cancellation: a pairing that finishes after it was
/// stopped, as a handshake already under way does.
@MainActor
private final class PairingHold {
    var isHolding = false
    private var waiting: [CheckedContinuation<Void, Never>] = []

    var held: Int { waiting.count }

    func wait() async {
        guard isHolding else { return }
        await withCheckedContinuation { waiting.append($0) }
    }

    func release() {
        isHolding = false
        for continuation in waiting { continuation.resume() }
        waiting = []
    }
}

/// The network a check's fakes stand for: one fixture host, and every link made to it.
@MainActor
private final class FixtureNetwork {
    static let peerInfo = PeerInfo(name: "Fixture", version: "1", build: "1")

    let reached = Reached()
    let host = FixtureHost()
    var answer = FixtureLink.Answer.serve
    private(set) var links: [FixtureLink] = []
    let pairing = PairingHold()
    /// What pair over SSH prints, if anything.
    var sshInvite: PairingInvite?

    var invite: PairingInvite {
        PairingInvite(
            hostID: host.hostID, hostKey: host.hostKey, secret: Data(repeating: 1, count: 32), hostName: "Fixture",
            expiresAt: .now.addingTimeInterval(300), addresses: [], grants: AddHostModel.sshOffer)
    }

    func pairedHost() -> PairedHost {
        PairedHost(
            result: LinkPairingResult(
                hostID: host.hostID, hostKey: host.hostKey, hostName: "Fixture", deviceID: UUID(), grants: LinkGrants(),
                addresses: []), identity: LinkIdentity())
    }

    #if !BEFORE
    var reach: RemoteHostsPolicy.Reach {
        RemoteHostsPolicy.Reach(
            connect: { [self] remote in
                let link = FixtureLink(host: host, reached: reached, answer: answer)
                links.append(link)
                remote.start(using: NativeHostClient(transport: link, clientInfo: Self.peerInfo))
            },
            browse: { [reached] in FixtureBrowser(reached) },
            pair: { [self] invite, device, _, _ in
                reached.note("pair")
                await pairing.wait()
                return PairedHost(
                    result: LinkPairingResult(
                        hostID: invite.hostID, hostKey: invite.hostKey, hostName: invite.hostName, deviceID: UUID(),
                        grants: device.requestedGrants ?? LinkGrants(), addresses: []), identity: LinkIdentity())
            },
            ssh: { [self] _, _, _ in
                reached.note("ssh")
                let link = sshInvite.map { $0.url.absoluteString }
                return AsyncStream { [reached] continuation in
                    continuation.onTermination = { _ in reached.note("sshStopped") }
                    if let link { continuation.yield(.event(LinkPairCommandEvent(event: .invite, link: link))) }
                }
            })
    }
    #endif
}

@main
@MainActor
private struct DroidManagedPolicyRegression {
    static func main() async {
        do {
            switch UserDefaults.standard.string(forKey: "check") {
            case "repro": try await repro()
            case "matrix": try await matrix()
            default: throw PolicyFailure("Pass -check repro or -check matrix")
            }
        } catch {
            print("FAIL: \(error)")
            exit(1)
        }
    }

    static func require(_ condition: Bool, _ message: String) throws {
        if !condition { throw PolicyFailure(message) }
    }

    static func wait(_ what: String, _ condition: () async -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(10)
        while !(await condition()) {
            guard ContinuousClock.now < deadline else { throw PolicyFailure("Timed out: \(what)") }
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    /// Long enough for anything already set off to have reached out.
    static func settle() async throws {
        try await Task.sleep(for: .milliseconds(400))
    }

    static func makeApp(hosts: RemoteHosts) -> AppModel {
        let defaults = PreviewUserDefaults()
        let manifest = PluginManifest(
            id: "fixture", name: "Fixture",
            agents: [AgentManifest(id: "fixture", name: "Fixture", command: "/usr/bin/true")])
        let app = AppModel(
            plugins: PluginRegistry(builtIns: [ManifestPlugin(manifest: manifest)], defaults: defaults),
            defaults: defaults, catalogURL: nil, hosts: hosts)
        _ = app.runtimes.sync()
        // The app's wiring (AppModel.startRemoteHosts), without the notification plugins.
        app.hosts.onEvent = { _, event in
            app.sessions.handle(event)
            if case .sessionChanged = event { app.indexRemoteSessions() }
        }
        app.hosts.onRefreshed = { host in Task { await app.hostConnected(host) } }
        return app
    }

    // MARK: - The app's own policy

    /// The app's policy and network code, as the launch arguments set them: a paired host is
    /// connected to exactly when remote hosts are on and the organization doesn't turn them off.
    static func repro() async throws {
        let policy = PolicyCenter.shared.policy
        let managedOff = policy.isManaged(.remoteHostsEnabled) && !policy.remoteHostsEnabled
        let featureOn = UserDefaults.standard.bool(forKey: "NativeRemoteHosts")
        try require(
            UserDefaults.standard.bool(forKey: "NativeRemoteHostsLoopbackOnly"),
            "Run with -NativeRemoteHostsLoopbackOnly YES, so nothing browses this network")
        let expected = featureOn && !managedOff
        let paired = PairedHost(
            result: LinkPairingResult(
                hostID: HostID(), hostKey: LinkIdentity().publicKey, hostName: "Fixture", deviceID: UUID(),
                grants: LinkGrants(), addresses: []), identity: LinkIdentity())
        let hosts = RemoteHosts(store: MemoryPairedHostStore([paired]))
        let app = makeApp(hosts: hosts)
        let setting = "feature \(featureOn ? "on" : "off"), policy \(managedOff ? "managed off" : "not off")"
        hosts.start()
        let connected = hosts.all.contains { $0.client != nil }
        for host in hosts.all { host.stop() }
        try require(
            connected == expected, expected ? "Didn't connect with \(setting)" : "Connected to a host with \(setting)")
        try require(RemoteHosts.isEnabled == expected, "RemoteHosts.isEnabled is \(!expected) with \(setting)")
        try require(app.offersRemoteHosts == expected, "The app offers remote hosts \(!expected) with \(setting)")
        print("PASS: \(expected ? "connects" : "reaches no host") with \(setting)")
    }

    // MARK: - Policies changing during the run

    static func matrix() async throws {
        #if BEFORE
        throw PolicyFailure("The matrix needs the fix")
        #else
        try await allowed()
        try await turnedOffAtLaunch()
        try await featureOff()
        try await noPairedDevices()
        try await offWhilePairingByLink()
        try await offWhilePairingByLink(organizationName: "Northwind Federal IT")
        try await offWhilePairingByLink(organizationName: "Northwind Federal IT", organizationContact: "#it-help")
        try await offWhilePairingOverSSH()
        try await offBeforeSubmitting()
        try await offWhileReconnecting()
        try await offWithOpenTask()
        try await offAtLaunchThenAllowed()
        try await testPairingHook()
        #endif
    }

    #if !BEFORE
    /// A check's own policy, hosts model and app, all on fakes.
    @MainActor
    struct Fixture {
        let network: FixtureNetwork
        let source: ScratchPolicy
        let store: MemoryPairedHostStore
        let hosts: RemoteHosts
        let app: AppModel
        let policy: RemoteHostsPolicy

        var reached: Reached { network.reached }

        func addHost() -> AddHostModel {
            AddHostModel(register: { [hosts] in hosts.add($0) }, environment: { [:] }, policy: policy)
        }

        func stop() {
            for host in hosts.all { host.stop() }
        }
    }

    static func fixture(
        policy value: Bool?, isFeatureOn: Bool = true, paired: Bool = true, organizationName: String? = nil,
        organizationContact: String? = nil
    ) -> Fixture {
        let network = FixtureNetwork()
        let source = ScratchPolicy(value, organizationName: organizationName, organizationContact: organizationContact)
        let center = PolicyCenter(source: source)
        center.start()
        let policy = RemoteHostsPolicy(center: center, isFeatureOn: isFeatureOn, reach: network.reach)
        let store = MemoryPairedHostStore(paired ? [network.pairedHost()] : [])
        let hosts = RemoteHosts(store: store, policy: policy)
        return Fixture(
            network: network, source: source, store: store, hosts: hosts, app: makeApp(hosts: hosts), policy: policy)
    }

    static func isFailed(_ model: AddHostModel) -> Bool {
        if case .failed = model.phase { true } else { false }
    }

    /// Asks Add Host for an SSH destination, then for a link: both stop before reaching anything.
    static func requireAddHostRefuses(_ fixture: Fixture, _ setting: String) async throws {
        let model = fixture.addHost()
        model.input = "me@fixture.local"
        model.submit()
        try require(isFailed(model), "Add Host went on over SSH with \(setting)")
        model.input = fixture.network.invite.url.absoluteString
        model.submit()
        try require(isFailed(model), "Add Host took a link with \(setting)")
        try await settle()
        try require(fixture.reached.attempts == 0, "Add Host reached out with \(setting)")
    }

    static func allowed() async throws {
        for value in [nil, true] {
            let fixture = fixture(policy: value)
            let setting = value == nil ? "no policy" : "a managed true"
            fixture.hosts.start()
            try await wait("connects with \(setting)") { fixture.hosts.all.first?.isOnline == true }
            try require(fixture.reached.count("browse") == 1, "Didn't browse for the paired host with \(setting)")
            try require(fixture.hosts.isEnabled && fixture.app.offersRemoteHosts, "Remote hosts off with \(setting)")
            fixture.stop()
        }
        print("PASS: no policy and a managed true connect and browse")
    }

    static func turnedOffAtLaunch() async throws {
        let fixture = fixture(policy: false)
        let setting = "-NativeRemoteHosts YES and a managed false"
        fixture.hosts.start()
        try await settle()
        try require(!fixture.hosts.isEnabled && !fixture.app.offersRemoteHosts, "Remote hosts on with \(setting)")
        try require(fixture.reached.attempts == 0, "Reached a host with \(setting)")
        try require(
            !(await fixture.app.loadRemoteSession(SessionKey(agent: .init(rawValue: "fixture"), id: SessionID("task")))),
            "Opened a remote task with \(setting)")
        try await requireAddHostRefuses(fixture, setting)
        // A pairing that finishes late is kept for later, and not connected to.
        fixture.hosts.add(FixtureNetwork().pairedHost())
        try await settle()
        try require(try fixture.store.hosts().count == 2, "A pairing made meanwhile wasn't kept")
        try require(fixture.reached.attempts == 0, "Connected to a pairing made with \(setting)")
        print("PASS: a managed false wins over -NativeRemoteHosts YES: nothing connects, browses or pairs")
    }

    static func featureOff() async throws {
        let fixture = fixture(policy: nil, isFeatureOn: false)
        fixture.hosts.start()
        try await settle()
        try require(!fixture.hosts.isEnabled && !fixture.app.offersRemoteHosts, "Remote hosts on with the feature off")
        try require(fixture.reached.attempts == 0, "Reached a host with the feature off")
        try await requireAddHostRefuses(fixture, "the feature off")
        print("PASS: with NativeRemoteHosts off nothing connects, browses or pairs")
    }

    static func noPairedDevices() async throws {
        let off = fixture(policy: false, paired: false)
        off.hosts.start()
        let on = fixture(policy: nil, paired: false)
        on.hosts.start()
        try await settle()
        try require(off.reached.attempts == 0 && on.reached.attempts == 0, "Reached out with no paired host")
        let model = on.addHost()
        model.input = on.network.invite.url.absoluteString
        model.submit()
        model.pair()
        try await wait("pairs by link") { if case .paired = model.phase { true } else { false } }
        try await wait("connects to the new host") { on.hosts.all.first?.isOnline == true }
        try require(on.reached.count("browse") == 1, "Didn't browse once paired")
        on.stop()
        print("PASS: with no paired host nothing reaches out until Add Host pairs one")
    }

    static func offWhilePairingByLink(organizationName: String? = nil, organizationContact: String? = nil) async throws
    {
        let fixture = fixture(
            policy: nil, paired: false, organizationName: organizationName, organizationContact: organizationContact)
        fixture.hosts.start()
        let model = fixture.addHost()
        model.input = fixture.network.invite.url.absoluteString
        model.submit()
        fixture.network.pairing.isHolding = true
        model.pair()
        try await wait("pairing in flight") { fixture.network.pairing.held == 1 }
        fixture.source.set(false)
        try await wait("pairing stops") { isFailed(model) }
        try requireOrganizationStopped(model, organizationName: organizationName)
        try require(model.organizationContact == organizationContact, "Lost the configured help contact")
        if let organizationContact {
            guard case .failed(let failure) = model.phase else { throw PolicyFailure("Missing policy failure") }
            try require(
                model.suggestion(for: failure).contains("Ask in \(organizationContact) to turn remote hosts on."),
                "Didn't show where to ask for help")
        }
        fixture.network.pairing.release()
        try await settle()
        try require(isFailed(model), "A pairing that finished after the policy turned off was shown as paired")
        try require(fixture.hosts.all.isEmpty && (try fixture.store.hosts()).isEmpty, "Kept a pairing made after off")
        try require(fixture.reached.count("connect") == 0, "Connected to a pairing made after off")
        try require(!model.canRetryPairing && model.isBlockedByOrganization, "Offered link recovery while blocked")
        let input = model.input
        fixture.source.set(true)
        try await wait("link recovery allowed again") { model.canRetryPairing }
        try require(!model.isBlockedByOrganization && !model.canTryAgain, "Offered SSH retry for a pasted link")
        guard case .failed(let failure) = model.phase else { throw PolicyFailure("Lost the pairing failure") }
        try require(
            model.suggestion(for: failure).contains("Remote hosts are allowed again."),
            "Still said remote hosts were off after the organization allowed pairing")
        model.edit()
        try require(model.phase == .entering && model.input == input, "Lost the original link after policy allowed it")
        print("PASS: a policy stop keeps nothing paired, preserves the link and allows recovery only when on again")
    }

    static func requireOrganizationStopped(_ model: AddHostModel, organizationName: String? = nil) throws {
        guard case .failed(let failure) = model.phase else {
            throw PolicyFailure("Add Host didn't show a failure after the organization turned hosts off")
        }
        try require(
            failure == .organizationTurnedOff(name: organizationName),
            "Policy stop didn't use the organization-specific failure")
        try require(
            failure.title == "Turned off by your organization",
            "Policy stop showed the wrong title: \(failure.title)")
        try require(failure.recovery == "Nothing was paired.", "Policy stop didn't explain that nothing was paired")
        try require(!failure.isWorthRetrying, "A policy stop offered retry before the organization allowed pairing")
        try require(!model.canTryAgain, "SSH retry was available while the organization blocked pairing")
        let input = model.input
        model.retry()
        try require(model.phase == .failed(failure), "Retry left the policy failure while hosts were blocked")
        try require(model.input == input, "A policy stop lost the original destination or link")
        for overSSH in [false, true] {
            try require(
                failure.suggestion(overSSH: overSSH)
                    == "\(organizationName ?? "Your organization") turned off remote hosts on this Mac. Ask them to turn remote hosts on.",
                "Policy stop didn't explain who turned hosts off and what to do next")
        }
    }

    static func offWhilePairingOverSSH() async throws {
        let fixture = fixture(policy: nil, paired: false)
        fixture.hosts.start()
        let model = fixture.addHost()
        model.input = "me@fixture.local"
        model.submit()
        try await wait("ssh runs") { fixture.reached.count("ssh") == 1 }
        fixture.source.set(false)
        try await wait("ssh stops while reaching") { isFailed(model) && fixture.reached.count("sshStopped") == 1 }
        try requireOrganizationStopped(model)
        try require(model.isBlockedByOrganization && !model.canRetryPairing, "Offered SSH recovery while blocked")
        // On again, as far as the link: pair printed it and is waiting.
        fixture.source.set(true)
        try await wait("on again") { fixture.hosts.isEnabled }
        try require(model.canTryAgain && !model.isBlockedByOrganization, "Didn't offer SSH retry when allowed again")
        try require(model.input == "me@fixture.local", "Lost the SSH destination while policy blocked pairing")
        fixture.network.sshInvite = fixture.network.invite
        model.retry()
        try await wait("link over ssh") { if case .confirming = model.phase { true } else { false } }
        fixture.source.set(false)
        try await wait("ssh stops while confirming") { isFailed(model) && fixture.reached.count("sshStopped") == 2 }
        try requireOrganizationStopped(model)
        model.pair()
        try await settle()
        try require(fixture.reached.count("pair") == 0, "Paired after the policy turned off")
        print("PASS: turning off during SSH pairing ends ssh, reaching or confirming")
    }

    static func offBeforeSubmitting() async throws {
        let fixture = fixture(policy: nil, paired: false)
        let model = fixture.addHost()
        model.input = "me@fixture.local"
        fixture.source.set(false)
        try await wait("off before Continue") { !fixture.policy.isEnabled }
        model.submit()
        try requireOrganizationStopped(model)
        try require(fixture.reached.attempts == 0, "Reached a host while Continue was blocked")
        fixture.source.set(true)
        try await wait("Continue allowed again") { model.canRetryPairing }
        try require(model.canTryAgain, "Mistook the blocked SSH destination for a pasted link")
        model.retry()
        try await wait("retried original destination") { fixture.reached.count("ssh") == 1 }
        model.stop()
        print("PASS: a policy stop before Continue preserves the SSH destination for retry when allowed")
    }

    static func offWhileReconnecting() async throws {
        let fixture = fixture(policy: nil)
        fixture.network.answer = .unreachable
        fixture.hosts.start()
        try await wait("reconnecting") { fixture.reached.count("connect") >= 2 }
        fixture.source.set(false)
        try await wait("stops") {
            fixture.reached.count("browseStopped") == 1 && fixture.hosts.all.allSatisfy { $0.client == nil }
        }
        let tries = fixture.reached.count("connect")
        try await Task.sleep(for: .milliseconds(1_500))
        try require(fixture.reached.count("connect") == tries, "Kept reconnecting after the policy turned off")
        try require(fixture.hosts.all.count == 1 && (try fixture.store.hosts()).count == 1, "Lost the pairing")

        // A connection under way when it turns off is cancelled.
        fixture.network.answer = .hold
        fixture.source.set(true)
        try await wait("connecting again") { fixture.reached.count("connect") == tries + 1 }
        fixture.source.set(false)
        try await wait("connection cancelled") { fixture.reached.count("connectCancelled") == 1 }
        try await settle()
        try require(fixture.reached.count("connect") == tries + 1, "Connected again after the policy turned off")
        print("PASS: turning off while reconnecting stops the retries and cancels a connection under way")
    }

    static func offWithOpenTask() async throws {
        let fixture = fixture(policy: nil)
        let host = fixture.network.host
        let app = fixture.app
        await host.log(.reset(loading: false))
        await host.log(.prompt(PromptEcho(text: "hello")))
        await host.log(chunk("Hi"))
        await host.log(.turnEnded(stopReason: "end_turn"))
        let project = app.projects.add(URL(filePath: "/fixture/repo"))
        fixture.hosts.start()
        try await wait("connects") {
            fixture.hosts.all.first?.isOnline == true && fixture.hosts.all.first?.sessions.isEmpty == false
        }
        guard let remote = fixture.hosts.all.first, let first = remote.client else {
            throw PolicyFailure("No connected host")
        }
        let paired = remote.paired
        app.setCheckout(project.path, of: project.id, on: remote.id)
        let key = SessionKey(agent: .init(rawValue: "fixture"), id: SessionID("task"))
        try require(await app.loadRemoteSession(key), "Remote task didn't open")
        guard let session = app.sessions.session(key) else { throw PolicyFailure("No model for the task") }
        try require(session.host?.client === first, "Task isn't on the host's client")
        try await wait("task caught up") { await caughtUp(session, with: host) }
        session.draft = "Keep this draft"
        guard let link = fixture.network.links.first else { throw PolicyFailure("No link") }

        fixture.source.set(false)
        try await wait("connection closes") { fixture.reached.count("closed") == 1 }
        let calls = await link.calls
        await host.log(chunk(" while off"))
        try await settle()
        try require(await link.calls == calls, "Made requests after the policy turned off")
        try require(fixture.network.links.count == 1, "Connected again while off")
        try require(!app.offersRemoteHosts, "Still offers remote hosts while off")
        let forbidden = [HostProtocol.Method.cancel, HostProtocol.Method.closeSession, HostProtocol.Method.shutdown]
        try require(!calls.contains(where: forbidden.contains), "Stopped the host's task or the host")
        // The key this Mac holds for the host, here and saved.
        let keys = fixture.hosts.all.map(\.paired.deviceKey) + (try fixture.store.hosts()).map(\.deviceKey)
        try require(keys == [paired.deviceKey, paired.deviceKey], "Changed or forgot the pairing")
        try require(app.sessions.session(key) === session && session.draft == "Keep this draft", "Lost the task")
        // Still the host's task, so its files and tools never resolve on this Mac.
        try require(app.device(of: key) == .remote(remote.id), "The open task passes for this Mac's while off")
        try require(app.hosts.hostID(of: first) == remote.id, "The task's client lost its host while off")

        fixture.source.set(true)
        try await wait("connects again") { fixture.hosts.all.first?.isOnline == true }
        guard let second = fixture.hosts.all.first?.client, second !== first else {
            throw PolicyFailure("No new client")
        }
        try await wait("task moves to the new client") { session.host?.client === second }
        try await wait("catches up on what happened while off") { await caughtUp(session, with: host) }
        try await settle()
        try require(fixture.reached.count("connect") == 2, "Connected more than once on again")
        try require(fixture.network.links.count == 2, "Made more than one new client")
        try require(session.draft == "Keep this draft", "Lost the draft")
        try require(app.device(of: key) == .remote(remote.id), "The task changed device on again")
        fixture.stop()
        print("PASS: turning off closes the connection and leaves the task and pairing; on again reconnects once")
    }

    static func offAtLaunchThenAllowed() async throws {
        let fixture = fixture(policy: false)
        fixture.hosts.start()
        fixture.source.set(nil)
        try await settle()
        try require(fixture.reached.attempts == 0, "Reached a host in a run that began with remote hosts off")
        try require(!fixture.hosts.isEnabled, "Remote hosts on in a run that began with them off")
        print("PASS: a run that began with remote hosts off waits for the next launch")
    }

    static func testPairingHook() async throws {
        let link = FixtureNetwork().invite.url.absoluteString
        UserDefaults.standard.register(defaults: ["NativeRemoteHostsPairLink": link])
        let off = fixture(policy: false, paired: false)
        off.hosts.start()
        off.source.set(nil)
        try await settle()
        try require(off.reached.attempts == 0, "The launch's test pairing ran with remote hosts off")

        let on = fixture(policy: nil, paired: false)
        on.network.pairing.isHolding = true
        on.hosts.start()
        try await wait("test pairing in flight") { on.network.pairing.held == 1 }
        on.source.set(false)
        try await wait("off") { !on.hosts.isEnabled }
        on.network.pairing.release()
        try await settle()
        try require(on.hosts.all.isEmpty && (try on.store.hosts()).isEmpty, "Kept a test pairing made after off")
        try require(on.reached.count("connect") == 0, "Connected to a test pairing made after off")
        print("PASS: the launch's test pairing checks the policy before and after")
    }

    static func chunk(_ text: String) -> HostEvent.Payload {
        .update(
            .object([
                "sessionUpdate": .string("agent_message_chunk"),
                "content": .object(["type": .string("text"), "text": .string(text)]),
            ]))
    }

    /// Whether the task's transcript here is the host's, without duplicates or gaps.
    static func caughtUp(_ session: SessionModel, with host: FixtureHost) async -> Bool {
        var mirror = SessionMirror()
        mirror.apply(await host.log)
        return shape(session.state.items) == shape(mirror.state.items)
    }

    static func shape(_ items: [TranscriptItem]) -> [String] {
        items.map { item in
            if case .message(let message) = item {
                "\(message.role): \(message.text)"
            } else {
                String(String(describing: item).prefix { $0 != "(" })
            }
        }
    }
    #endif
}
