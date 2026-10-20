import Foundation
import NativeHostProtocol

extension MetaKey {
    /// The keep-awake policy clients last set, as JSON, so it holds across restarts with no client.
    static let keepAwakePolicy = "keep_awake_policy"
}

// How the host's machine is doing (`_native/host/status`) and keeping it awake while sessions work
// (docs/durability.md, "Sleep"). Clients hear `status/changed` about every 30 seconds while
// connected, and at once when keeping awake changes.
extension HostCore {
    static let statusInterval = Duration.seconds(30)

    /// The keep-awake engine, with the policy the store remembers. For `HostCore.keepAwake`.
    func makeKeepAwake() -> HostKeepAwakeEngine {
        let stored = (try? store.meta(MetaKey.keepAwakePolicy)).flatMap { $0 }.flatMap {
            try? JSONDecoder().decode(KeepAwakePolicy.self, from: Data($0.utf8))
        }
        return HostKeepAwakeEngine(backend: configuration.keepAwake, policy: stored ?? KeepAwakePolicy())
    }
}

extension HostCore {
    /// At startup: keeping awake applies the remembered policy, and connected clients hear how the
    /// machine is doing every so often.
    func startHostStatus() {
        keepAwake.onChange = { [weak self] _ in
            self?.publishStatus()
        }
        keepAwake.start(workingAgents: workingSessionCount)
        Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.statusInterval)
                guard let self else { return }
                if !clients.isEmpty {
                    publishStatus()
                }
            }
        }
    }

    /// After any session changed: keeping awake follows how many are working.
    func keepAwakeActivityChanged() {
        keepAwake.setWorkingAgents(workingSessionCount)
    }

    private var workingSessionCount: Int {
        sessions.values.count { $0.isWorking }
    }

    var hostStatus: HostStatus {
        let system = configuration.systemInfo ?? .portable
        return HostStatus(
            system: system.system, model: system.model, bootedAt: configuration.bootTime,
            loadAverage: system.loadAverage(), keepAwake: keepAwake.state, checkedAt: .now)
    }

    /// The owner sets this machine's policy (the app's Keep Mac Awake setting); paired devices only
    /// if they may manage the host.
    func setKeepAwake(_ policy: KeepAwakePolicy, by client: ClientLink) throws -> HostKeepAwakeState {
        guard client.grants.isLocal || client.grants.manageHost else {
            throw HostError.notAuthorized("keep this machine awake")
        }
        let json = String(decoding: try JSONEncoder().encode(policy), as: UTF8.self)
        try store.setMeta(MetaKey.keepAwakePolicy, json)
        keepAwake.setPolicy(policy)
        return keepAwake.state
    }

    func publishStatus() {
        let notification = HostStatusChangedNotification(status: hostStatus)
        for client in clients.values {
            client.notify(HostProtocol.Method.hostStatusChanged, notification)
        }
    }
}
