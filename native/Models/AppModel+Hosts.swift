import ACP
import Foundation
import NativeHostClient
import NativeHostProtocol
import NativeLink
import os

// Paired hosts sessions run on besides this Mac (`RemoteHosts`), and projects across devices: which
// device has a checkout of a project, which one a new session starts on, and which one each session
// lives on (`docs/durability.md`, "Host identity and many hosts").
extension AppModel {
    /// Whether paired hosts are offered now: turned on for this run, and allowed by the
    /// organization (`RemoteHostsPolicy`).
    var offersRemoteHosts: Bool {
        hosts.isEnabled
    }

    /// Connects to every paired host and routes their sessions' events to the models here. Called
    /// once from `start()`.
    func startRemoteHosts() {
        hosts.definition = { [weak self] agent in
            self?.plugins.agent(AgentDefinition.ID(rawValue: agent.id)) ?? RemoteHost.definition(from: agent)
        }
        hosts.onEvent = { [weak self] host, event in
            self?.receive(event, from: host)
        }
        hosts.onRefreshed = { [weak self] host in
            Task { await self?.hostConnected(host) }
        }
        launcher.isRemote = { [hosts] client in hosts.hostID(of: client) != nil }
        hosts.start()
    }

    private func receive(_ event: NativeHostClient.Event, from host: RemoteHost) {
        if let client = host.client {
            // Notifications from every paired host, named (docs/durability.md, "Notifications").
            BuiltInPlugins.usage.hostNotifications.receive(event, from: client, name: host.name)
        }
        switch event {
        case .sessionEvent:
            sessions.handle(event)
        case .sessionChanged, .sessionClosed:
            sessions.handle(event)
            indexRemoteSessions()
        default:
            break
        }
    }

    // MARK: - Devices

    /// What the picker and badges call a device: "This Mac", or the host's name here.
    func deviceName(_ device: SessionDevice) -> String {
        switch device {
        case .thisMac: "This Mac"
        case .remote(let id): hosts.host(id)?.name ?? "Unknown host"
        }
    }

    /// The device a session lives on: the host whose client holds its model, or whose sessions list
    /// it; else this Mac.
    func device(of session: SessionKey) -> SessionDevice {
        if let task = startingTask(session) { return task.device }
        if let remote = remoteSession(session) { return .remote(remote.host) }
        return remotePlace(of: session).map { .remote($0.host.id) } ?? .thisMac
    }

    /// Where a remote session lives: `(HostID, HostSessionID)`. Nil for this Mac's sessions. An open
    /// task's client says which host it's on, even a client retired while the task waits for the
    /// host's next one: a task on another machine never passes for this Mac's.
    func remoteSession(_ key: SessionKey) -> RemoteSessionRef? {
        if let link = sessions.session(key)?.host, let host = hosts.hostID(of: link.client) {
            return RemoteSessionRef(host: host, session: link.id)
        }
        for host in hosts.all {
            if let summary = host.sessions.first(where: {
                $0.agentID == key.agent.rawValue && $0.agentSessionID == key.id
            }) {
                return RemoteSessionRef(host: host.id, session: summary.id)
            }
        }
        return nil
    }

    // MARK: - Projects across devices

    /// The New Session device picker's rows for `project`: this Mac first, then each paired host in
    /// the order they were paired, each with whether it can take a session and the project there.
    func deviceOptions(for project: Project.ID) -> [SessionDeviceOption] {
        guard let project = projects.project(project) else { return [] }
        let thisMac = SessionDeviceOption(
            device: .thisMac, name: deviceName(.thisMac), availability: .online, checkout: .present(path: project.path))
        return [thisMac]
            + hosts.all.map { host in
                SessionDeviceOption(
                    device: .remote(host.id), name: host.name, availability: host.availability,
                    checkout: checkout(of: project, on: host))
            }
    }

    /// The project on `host`: its checkout there, or whether one can be cloned.
    private func checkout(of project: Project, on host: RemoteHost) -> SessionDeviceOption.Checkout {
        if let path = project.checkoutPath(on: .remote(host.id)) { return .present(path: path) }
        guard project.remoteURL != nil else { return .cannotClone(reason: "This project has no remote to clone from.") }
        guard host.paired.grants.runCommands else {
            return .cannotClone(
                reason:
                    "\(host.name) was paired without running commands, so Native can't clone onto it. Pair it again to allow that."
            )
        }
        return .willClone
    }

    /// The device a new session in `project` starts on unless the user picks another: the one used
    /// last for it while it can take a session, else this Mac.
    func preferredDevice(for project: Project.ID) -> SessionDevice {
        guard let remembered = ProjectDevicePreference.device(for: project),
            deviceOptions(for: project).first(where: { $0.device == remembered })?.canStart == true
        else { return .thisMac }
        return remembered
    }

    /// Records `path` as `project`'s checkout on `host` (one per host).
    func setCheckout(_ path: String, of project: Project.ID, on host: RemoteHostID) {
        projects.update(project) { project in
            project.checkouts.removeAll { $0.host == host }
            project.checkouts.append(ProjectCheckout(host: host, path: path))
        }
    }

    /// Forgets `project`'s checkout on `host`; the folder stays there.
    func removeCheckout(of project: Project.ID, on host: RemoteHostID) {
        projects.update(project) { $0.checkouts.removeAll { $0.host == host } }
    }
}

extension RemoteHost {
    /// How the device picker shows the host now.
    var availability: SessionDeviceOption.Availability {
        switch phase {
        case .connected: .online
        case .connecting, .reconnecting: .connecting
        case .unreachable(let reason): .offline(reason: "Not reachable. \(reason)")
        case .incompatible(let version, let host):
            .offline(
                reason: version < HostProtocol.version
                    ? "Runs Native \(host.version), which is older than this Mac's. Update Native on \(name)."
                    : "Runs Native \(host.version), which is newer than this Mac's. Update Native here.")
        case .pairingEnded(let error): .offline(reason: error.localizedDescription)
        }
    }
}

extension SessionDeviceOption.Availability {
    var reason: String? {
        if case .offline(let reason) = self { reason } else { nil }
    }
}

/// The device each project's new sessions last started on, so the picker defaults to it.
enum ProjectDevicePreference {
    private static func key(_ project: Project.ID) -> String {
        "projectDevice.\(project.uuidString)"
    }

    static func device(for project: Project.ID) -> SessionDevice? {
        UserDefaults.standard.data(forKey: key(project)).flatMap {
            try? JSONDecoder().decode(SessionDevice.self, from: $0)
        }
    }

    static func remember(_ device: SessionDevice, for project: Project.ID) {
        guard let data = try? JSONEncoder().encode(device) else { return }
        UserDefaults.standard.set(data, forKey: key(project))
    }
}
