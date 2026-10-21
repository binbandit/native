import ACP
import Foundation
import NativeHostClient
import NativeHostProtocol
import NativeLink
import SwiftUI

/// Settings ▸ Hosts from the app's own hosts: This Mac (its agents, and its background host's
/// connection) and every paired host (`RemoteHosts`). Made fresh for each render: everything it
/// reads is observable, so the page follows the hosts as they change.
struct AppHostsDirectory: HostsDirectory {
    let model: AppModel
    let durableHost: DurableHost?
    let looks: HostLookStore
    let openAddHost: (() -> Void)?

    var hosts: [HostDisplay] {
        [thisMac] + model.hosts.all.map(display)
    }

    var problem: String? {
        model.hosts.problem
    }

    var canAddHost: Bool {
        openAddHost != nil
    }

    func addHost() {
        openAddHost?()
    }

    func rename(_ host: RemoteHostID, to name: String) {
        model.hosts.rename(host, to: name)
    }

    func setLook(_ look: HostLook, for device: SessionDevice) {
        looks.setLook(look, for: device)
    }

    func remove(_ host: RemoteHostID) -> (() -> Void)? {
        guard let removed = model.hosts.remove(host) else { return nil }
        return { [model] in model.hosts.restore(removed.paired, at: removed.index) }
    }

    func restartLocalHost() async {
        await durableHost?.startHostAgain()
    }

    func setKeepAwake(_ mode: KeepAwakeMode, on device: SessionDevice) async throws {
        guard case .remote(let id) = device else { return }
        let host = try remoteHost(id)
        guard let client = host.client, var policy = host.status?.keepAwake.policy else {
            throw NativeHostClient.Failure.notConnected
        }
        policy.mode = mode
        // The host pushes its new status at once, which updates the page.
        _ = try await client.setKeepAwake(policy)
    }

    func doctorClient(for device: SessionDevice) -> NativeHostClient? {
        switch device {
        case .thisMac: durableHost?.placement.usesHost == true ? durableHost?.client : nil
        case .remote(let id): model.hosts.host(id).flatMap { $0.isOnline ? $0.client : nil }
        }
    }

    func signIn(
        _ agent: AgentDefinition.ID, on device: SessionDevice, with method: AuthMethod, apiKey: String?
    )
        async throws
    {
        switch device {
        case .thisMac:
            // The app's own sign-in, which opens the terminal sheet for terminal-only methods and
            // reports its own failures.
            await model.signIn(to: agent, with: method)
        case .remote(let id):
            let host = try remoteHost(id)
            if let apiKey {
                try await host.signIn(agent, with: method, apiKey: apiKey)
            } else {
                try await host.signIn(agent, with: method)
            }
        }
    }

    func removeAPIKey(_ agent: AgentDefinition.ID, on device: SessionDevice, for method: AuthMethod) async throws {
        guard case .remote(let id) = device else { return }
        try await remoteHost(id).removeAPIKey(agent, for: method)
    }

    func cancelSignIn(_ agent: AgentDefinition.ID, on device: SessionDevice) async {
        guard case .remote(let id) = device else { return }
        try? await model.hosts.host(id)?.cancelSignIn(agent)
    }

    func checkAgain(_ agent: AgentDefinition.ID, on device: SessionDevice) async throws {
        switch device {
        case .thisMac:
            await model.checkForAgents()
            if model.runtime(agent)?.needsSignIn == true { await model.restart(agent) }
        case .remote(let id):
            let host = try remoteHost(id)
            if host.runtime(agent)?.isReady == true {
                try await host.checkSignIn(agent)
            } else {
                await host.startAgent(agent)
            }
        }
    }

    private func remoteHost(_ id: RemoteHostID) throws -> RemoteHost {
        guard let host = model.hosts.host(id) else { throw HostsDirectoryFailure.hostRemoved }
        return host
    }

    // MARK: - This Mac

    private var thisMac: HostDisplay {
        HostDisplay(
            device: .thisMac, name: "This Mac", machineName: PlatformDevice.name,
            look: looks.look(for: .thisMac, named: PlatformDevice.name), state: thisMacState,
            machine: HostMachineSummary(
                system: PlatformDevice.system, nativeVersion: Self.appVersion,
                bootedAt: Date.now.addingTimeInterval(-ProcessInfo.processInfo.systemUptime),
                loadAverage: Self.loadAverage),
            agents: model.agents.map { HostAgentDisplay($0, onHost: false) })
    }

    /// This Mac's background host, when agents run in it; agents running in the app are always here.
    private var thisMacState: HostDisplayState {
        guard let durableHost, durableHost.placement.usesHost else { return .online }
        return switch durableHost.connection {
        case .connected, nil: .online
        case .connecting: .connecting
        case .reconnecting(_, let reason): .reconnecting(reason: reason)
        case .unreachable(let reason): .offline(reason: reason, lastConnected: nil)
        case .incompatible(_, let peer):
            .needsUpdate(message: "Native's background host runs \(peer.version). Restart it to run this version.")
        }
    }

    private static var appVersion: String? {
        let info = Bundle.main.infoDictionary ?? [:]
        guard let version = info["CFBundleShortVersionString"] as? String else { return nil }
        return (info["CFBundleVersion"] as? String).map { "\(version) (\($0))" } ?? version
    }

    private static var loadAverage: Double? {
        var loads = [Double](repeating: 0, count: 1)
        return getloadavg(&loads, 1) == 1 ? loads[0] : nil
    }

    // MARK: - Paired hosts

    private func display(_ host: RemoteHost) -> HostDisplay {
        let machineName = host.paired.machineName
        let userSessions = host.sessions.filter { $0.origin == .user && $0.parentID == nil }
        return HostDisplay(
            device: .remote(host.id), name: host.name, machineName: machineName == host.name ? nil : machineName,
            look: looks.look(for: .remote(host.id), named: machineName), state: state(of: host),
            machine: HostMachineSummary(
                system: host.status?.system,
                nativeVersion: host.info.map { "\($0.hostInfo.version) (\($0.hostInfo.build))" },
                bootedAt: host.status?.bootedAt, loadAverage: host.status?.loadAverage,
                keepAwake: host.status.flatMap { Self.keepAwake($0.keepAwake) }),
            agents: host.runtimes.map { HostAgentDisplay($0, onHost: true) },
            sessions: HostSessionCounts(
                total: userSessions.count,
                working: userSessions.filter { $0.phase == .prompting || $0.phase == .recovering }.count),
            sshDestination: Self.sshDestination(host.paired),
            keepAwakeMode: host.status.flatMap { $0.keepAwake.isSupported ? $0.keepAwake.policy.mode : nil })
    }

    private func state(of host: RemoteHost) -> HostDisplayState {
        switch host.phase {
        case .connected: .online
        case .connecting: .connecting
        case .reconnecting(_, let reason): .reconnecting(reason: reason)
        case .unreachable(let reason): .offline(reason: reason, lastConnected: host.lastConnected)
        case .incompatible: .needsUpdate(message: host.availability.reason ?? "It runs another version of Native.")
        case .pairingEnded(let error): .pairingEnded(reason: error.localizedDescription)
        }
    }

    /// Whether the host stays awake for its tasks, in the words of the machine line.
    private static func keepAwake(_ state: HostKeepAwakeState) -> String? {
        guard state.isSupported else { return nil }
        return switch state.status.reason {
        case .alwaysOn, .timer: "Stays awake"
        case .agentsWorking, .waitingForAgents: "Awake while agents work"
        case .pausedOnBattery, .pausedLowBattery: "May sleep on battery"
        case .off: "May sleep"
        case .unknown: nil
        }
    }

    /// An address `ssh` reaches from here: a tailnet address works anywhere, a LAN one at home.
    /// Bonjour names are service names, not host names, so they're left out.
    private static func sshDestination(_ paired: PairedHost) -> String? {
        let preferred: [LinkAddress.Kind] = [.tailnet, .lan]
        return preferred.lazy.compactMap { kind in paired.addresses.first { $0.kind == kind }?.host }.first
    }
}

/// Why a Hosts page action couldn't happen.
enum HostsDirectoryFailure: LocalizedError {
    case hostRemoved

    var errorDescription: String? {
        switch self {
        case .hostRemoved: "That host isn't paired with this Mac anymore."
        }
    }
}

extension HostAgentDisplay {
    /// An agent as its runtime reports it. On a host it offers every way to sign in, the plugin's
    /// own included (an API key the agent reads); here, the ones the agent advertises, as
    /// Settings ▸ Agents does.
    init(_ runtime: AgentRuntime, onHost: Bool) {
        let agent = runtime.agent
        let methods = (onHost ? runtime.signInMethods : runtime.authMethods).compactMap {
            HostSignInMethod($0, agent: agent)
        }
        let terminalMethod = methods.lazy.compactMap { method -> String? in
            if case .terminal(let command) = method.kind { command } else { nil }
        }.first
        let auth = runtime.authStatus
        self.init(
            agent: agent, status: runtime.status, needsSignIn: runtime.needsSignIn, isSigningIn: runtime.isSigningIn,
            signInLabel: auth.map { [$0.label, $0.email].compactMap(\.self).joined(separator: " · ") },
            isSignedIn: auth?.isSignedIn, methods: methods, savedKeys: runtime.savedCredentials,
            terminalSignIn: agent.manifest.setup?.signIn ?? terminalMethod,
            installCommand: agent.manifest.setup?.install, docs: agent.manifest.setup?.docs,
            signInLink: runtime.signInLink, usesAPIKey: auth?.kind == .apiKey || !runtime.savedCredentials.isEmpty)
    }
}
