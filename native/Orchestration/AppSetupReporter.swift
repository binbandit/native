import ACP
import Foundation
import NativeHostClient
import NativeHostProtocol
import NativeLink
import NativePolicy
import NativeSetup

/// Builds `setup_status`'s report from the app's models: its build, every agent plugins provide,
/// the durable host, paired devices, the organization's policy and updates. It reads what Settings
/// shows and nothing more, so the report carries no paths, environment values or agent logs.
final class AppSetupReporter {
    /// Weak, as in `AppOrchestrationHost`: the model owns the plugins, which own this.
    private weak var model: AppModel?
    private weak var updates: UpdateController?
    private weak var durableHost: DurableHost?

    init(model: AppModel, updates: UpdateController?, durableHost: DurableHost?) {
        self.model = model
        self.updates = updates
        self.durableHost = durableHost
    }

    func report(callerAgent: AgentDefinition.ID) async -> SetupReport {
        let policy = PolicyCenter.shared.policy
        let version = AppVersion.current
        return SetupReport(
            native: .init(version: version.version, build: version.build, channel: Self.channel(version.channel)),
            agents: agents(policy: policy, caller: callerAgent),
            durableHost: host,
            pairedDevices: await pairedDevices(allowedByPolicy: policy.companionEnabled),
            organization: .init(
                managedKeys: policy.managedKeys.map(\.rawValue),
                ignoredKeys: policy.diagnostics.filter { $0.origin == .organization }.map(\.key)),
            updates: updateStatus
        )
    }

    // MARK: - Agents

    /// Every plugin's agents, off and disallowed ones included, in Settings ▸ Agents' order.
    private func agents(policy: NativePolicy, caller: AgentDefinition.ID) -> [SetupReport.Agent] {
        guard let model else { return [] }
        return model.plugins.plugins.flatMap { loaded in
            let plugin = loaded.plugin.manifest
            return plugin.agents.map { manifest in
                let definition = AgentDefinition(manifest, pluginID: plugin.id)
                var agent = SetupReport.Agent(
                    id: manifest.id, name: manifest.name, state: .ready, signIn: .unknown,
                    launch: ([manifest.command] + manifest.args).joined(separator: " "), requires: manifest.requires,
                    installCommand: manifest.setup?.install, signInCommand: manifest.setup?.signIn,
                    docs: manifest.setup?.docs, isCaller: definition.id == caller)
                if !policy.agents.allows(manifest.id) || !model.plugins.isAllowed(plugin.id) {
                    agent.state = .notAllowed
                } else if !model.plugins.isEnabled(plugin.id) {
                    agent.state = .turnedOff
                } else {
                    describe(&agent, availability: model.availability(of: definition), model: model)
                }
                return agent
            }
        }
    }

    private func describe(_ agent: inout SetupReport.Agent, availability: AgentAvailability, model: AppModel) {
        let id = AgentDefinition.ID(rawValue: agent.id)
        let runtime = model.runtime(id)
        if let info = runtime?.info {
            agent.version = [info.name, info.version].compactMap { $0 }.joined(separator: " ")
        }
        agent.offersSignIn = runtime?.authMethods.isEmpty == false
        switch availability {
        case .notInstalled(let missing):
            agent.state = .notInstalled
            agent.missingCommand = missing
        case .disabled: agent.state = .turnedOff
        case .starting: agent.state = .starting
        case .failed(let message):
            agent.state = .stopped
            agent.problem = SetupReport.headline(of: message)
        case .needsSignIn: agent.signIn = .needsSignIn
        case .signingIn: agent.signIn = .signingIn
        case .ready:
            // Signing in is only known once the agent accepts a session or turns one away.
            agent.signIn = model.sessions.open(of: id).isEmpty ? .unknown : .signedIn
        }
    }

    // MARK: - Durable host

    private var host: SetupReport.DurableHost {
        guard let durableHost, durableHost.isEnabled else { return .init(state: .off) }
        let versionStatus: SetupReport.DurableHost.VersionStatus =
            switch durableHost.versionStatus {
            case .matched: .matched
            case .hostRestartPending: .restartPending
            case .appOutdated: .appOutdated
            }
        switch durableHost.registration {
        case .needsApproval: return .init(state: .needsApproval)
        case .failed(let reason): return .init(state: .failed, problem: SetupReport.headline(of: reason))
        case .off, .enabled: break
        }
        return switch durableHost.connection {
        case nil, .connecting: .init(state: .starting)
        case .connected(let info):
            .init(state: .connected, version: info.hostInfo.version, versionStatus: versionStatus)
        case .reconnecting: .init(state: .reconnecting)
        case .unreachable(let reason): .init(state: .unreachable, problem: SetupReport.headline(of: reason))
        case .incompatible(_, let host):
            .init(state: .incompatible, version: host.version, versionStatus: versionStatus)
        }
    }

    // MARK: - Paired devices

    /// Asks the host's gateway once, the way Settings ▸ Paired Devices does while it's open.
    private func pairedDevices(allowedByPolicy: Bool) async -> SetupReport.PairedDevices {
        guard let durableHost, durableHost.isEnabled else {
            return .init(state: .hostOff, allowedByOrganization: allowedByPolicy)
        }
        let client = LinkControlClient(hostDirectory: durableHost.location.directory)
        await client.start()
        let event = await Self.firstEvent(of: client, within: .seconds(3))
        await client.stop()
        guard case .status(let status) = event else {
            var problem: String?
            if case .unavailable(let reason) = event { problem = SetupReport.headline(of: reason) }
            return .init(state: .waitingForHost, allowedByOrganization: allowedByPolicy, problem: problem)
        }
        let devices = status.activeDevices
        return .init(
            state: .available, paired: devices.count, connected: devices.filter(\.isConnected).count,
            acceptsConnections: status.isEnabled, listener: Self.listener(status.listener.state),
            pairingOpen: status.pairing?.phase == .open,
            allowedByOrganization: allowedByPolicy && status.isAllowedByPolicy != false,
            problem: status.listener.problem.map(SetupReport.headline))
    }

    private static func firstEvent(
        of client: LinkControlClient, within timeout: Duration
    ) async
        -> LinkControlClient.Event?
    {
        await withTaskGroup(of: LinkControlClient.Event?.self) { group in
            group.addTask {
                for await event in client.events {
                    return event
                }
                return nil
            }
            group.addTask {
                try? await Task.sleep(for: timeout)
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }

    private static func listener(_ state: LinkListenerStatus.State) -> SetupReport.PairedDevices.Listener {
        switch state {
        case .off: .off
        case .starting: .starting
        case .listening: .listening
        case .failed: .failed
        case .unknown: .unknown
        }
    }

    // MARK: - Updates

    private var updateStatus: SetupReport.Updates {
        guard let updates else {
            return .init(state: .unavailable, channel: .stable, automaticChecks: false, automaticDownloads: false)
        }
        let snapshot = updates.snapshot
        let state: SetupReport.Updates.State =
            switch snapshot.phase {
            case .idle: .idle
            case .checking: .checking
            case .upToDate: .upToDate
            case .available: .available
            case .downloading: .downloading
            case .ready: .ready
            case .installing: .installing
            case .failed: .failed
            case .unavailable: .unavailable
            }
        let channel: SetupReport.Updates.Channel =
            switch snapshot.channel {
            case .stable: .stable
            case .beta: .beta
            case .nightly: .nightly
            }
        return .init(
            state: state, channel: channel, availableVersion: snapshot.available?.version,
            automaticChecks: updates.automaticallyChecks, automaticDownloads: updates.automaticallyDownloads,
            lastChecked: snapshot.lastChecked, message: snapshot.message)
    }

    private static func channel(_ channel: ReleaseChannel) -> SetupReport.Build.Channel {
        switch channel {
        case .stable: .stable
        case .beta: .beta
        case .nightly: .nightly
        case .dev: .dev
        }
    }
}
