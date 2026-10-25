import ACP
import Foundation
import NativeHostProtocol

/// A task action's destination, captured before suspension or removal from the catalog. Kept for
/// undo and recovery; a reconnect resolves fresh services on this owner, never on a matching path.
struct TaskActionRoute {
    enum Owner: Hashable {
        case local
        case remote(RemoteHostID)
        case unavailableRemote
    }

    enum Failure: LocalizedError {
        case unavailable
        case missingCheckout
        case missingRoute
        case agentUnavailable(String)

        var errorDescription: String? {
            switch self {
            case .unavailable: "The task's host is unavailable. Reconnect it and retry."
            case .missingCheckout: "The task's project checkout on its host is unavailable. Reconnect it and retry."
            case .missingRoute: "The task's original host and workspace are no longer known. Nothing was changed."
            case .agentUnavailable(let reason): reason
            }
        }
    }

    let key: SessionKey
    let owner: Owner
    let project: Project
    let folder: URL?
    let title: String
    let hasCheckout: Bool
    /// Draft cleanup removes a workspace, but no agent session ever existed to run teardown for.
    var isDiscardedDraft = false

    var workspace: URL? {
        guard let folder else { return nil }
        let isProjectRoot: Bool
        switch owner {
        case .local: isProjectRoot = SessionFolder.isSame(folder.folderPath, project.path)
        case .remote, .unavailableRemote:
            isProjectRoot = RemoteHost.plain(folder.folderPath) == RemoteHost.plain(project.path)
        }
        return isProjectRoot ? nil : folder
    }

    var orderingKey: String {
        let path = (folder ?? project.url).standardizedFileURL.path(percentEncoded: false)
        switch owner {
        case .local: return path
        case .remote(let id): return "remote:\(id.rawValue):\(RemoteHost.plain(path))"
        case .unavailableRemote: return "unavailable:\(key.agent.rawValue):\(key.id):\(path)"
        }
    }
}

extension AppModel {
    /// Shared with host/session repair: capture synchronously, then pass the value across awaits.
    /// A saved route survives disappearing listings and catalog removal for the recovery lifetime.
    func taskActionRoute(for key: SessionKey) -> TaskActionRoute? {
        if let saved = hosts.deviceWorkspaces?.routes[key] {
            let owner = taskActionOwner(for: key)
            if owner == saved.owner { return saved }
            // A newly discovered identity collision invalidates the route rather than choosing
            // one of the tasks that the current SessionKey cannot distinguish.
            let unavailable = TaskActionRoute(
                key: saved.key, owner: .unavailableRemote, project: saved.project, folder: saved.folder,
                title: saved.title, hasCheckout: false, isDiscardedDraft: saved.isDiscardedDraft)
            hosts.deviceWorkspaces?.routes[key] = unavailable
            return unavailable
        }
        guard let listed = catalog.lookup(key), let project = projects.project(listed.project) else { return nil }
        let owner = taskActionOwner(for: key)
        let checkout: String?
        switch owner {
        case .local: checkout = project.path
        case .remote(let id): checkout = project.checkoutPath(on: .remote(id))
        case .unavailableRemote: checkout = nil
        }
        let route = TaskActionRoute(
            key: key, owner: owner,
            project: owner == .local ? project : checkout.map { project.onHost(at: $0) } ?? project,
            folder: sessions.session(key)?.cwd ?? URL(filePath: listed.info.cwd, directoryHint: .isDirectory),
            title: titleOfSession(key), hasCheckout: checkout != nil)
        return rememberTaskActionRoute(route)
    }

    /// Starting tasks have no catalog entry. Retain their explicit device before discard clears
    /// the folder, including when workspace preparation finishes after the user discarded it.
    func taskActionRoute(for task: StartingTask) -> TaskActionRoute? {
        guard let folder = task.folder, let project = projects.project(task.project) else { return nil }
        let owner: TaskActionRoute.Owner
        switch task.device {
        case .thisMac: owner = .local
        case .remote(let host): owner = .remote(host)
        }
        let checkout = project.checkoutPath(on: task.device)
        return rememberTaskActionRoute(
            TaskActionRoute(
                key: task.id, owner: owner,
                project: owner == .local ? project : checkout.map { project.onHost(at: $0) } ?? project,
                folder: folder, title: "New Task", hasCheckout: checkout != nil, isDiscardedDraft: true))
    }

    private func rememberTaskActionRoute(_ route: TaskActionRoute) -> TaskActionRoute {
        // The local provider is normally wired before any actions. Keep the route even with the
        // feature off, so a deleted local task's retries retain their original workspace too.
        if hosts.deviceWorkspaces == nil, let provider = taskWorkspaces {
            hosts.deviceWorkspaces = DeviceTaskWorkspaces(local: provider, model: self)
        }
        hosts.deviceWorkspaces?.routes[route.key] = route
        return route
    }

    func taskActionOwner(for key: SessionKey) -> TaskActionRoute.Owner {
        if let owner = hosts.deviceWorkspaces?.owners[key] {
            // SessionKey does not yet include a host. An ambiguous listing cannot safely mutate
            // either machine until that broader identity migration is made.
            let alsoLocal = (projects.all + projects.archived).contains { project in
                catalog.sessions(in: project.id, of: key.agent).contains { $0.sessionId == key.id }
            }
            return alsoLocal ? .unavailableRemote : owner
        }
        if let owner = hosts.deviceWorkspaces?.routes[key]?.owner { return owner }
        if let client = sessions.session(key)?.host?.client {
            if client === runtimes.host { return .local }
            return hosts.all.first { $0.client === client }.map { .remote($0.id) } ?? .unavailableRemote
        }
        if let place = remotePlace(of: key) { return .remote(place.host.id) }
        // A missing remote listing or pairing is not evidence that the task moved to this Mac.
        if catalog.remote[key] != nil { return .unavailableRemote }
        return .local
    }

    func workspaceProvider(for route: TaskActionRoute) throws -> (any TaskWorkspaceProvider)? {
        switch route.owner {
        case .local:
            return (taskWorkspaces as? DeviceTaskWorkspaces)?.local ?? taskWorkspaces
        case .remote(let id):
            guard route.hasCheckout else { throw TaskActionRoute.Failure.missingCheckout }
            guard let host = hosts.host(id), host.client != nil else {
                throw TaskActionRoute.Failure.unavailable
            }
            // Hosts without command execution can still run tasks in their project checkout.
            // That root has no workspace to put away or remove and needs no workspace service.
            if route.workspace == nil { return host.taskWorkspaces }
            guard let provider = host.taskWorkspaces else { throw TaskActionRoute.Failure.unavailable }
            return provider
        case .unavailableRemote:
            throw TaskActionRoute.Failure.unavailable
        }
    }

    func taskRuntime(for owner: TaskActionRoute.Owner, agent: AgentDefinition.ID) -> AgentRuntime? {
        switch owner {
        case .local: runtimes[agent]
        case .remote(let id):
            if let host = hosts.host(id), let client = host.client,
                let runtime = host.runtime(agent), runtime.host === client
            {
                runtime
            } else {
                nil
            }
        case .unavailableRemote: nil
        }
    }

    func deleteAgentCopy(using route: TaskActionRoute, startingIfNeeded: Bool) async throws {
        var runtime = taskRuntime(for: route.owner, agent: route.key.agent)
        if startingIfNeeded {
            switch route.owner {
            case .local: runtime = await ensureRunning(route.key.agent)
            case .remote:
                if let runtime, !runtime.isReady { await runtime.startOnHost() }
            case .unavailableRemote: break
            }
        }
        guard let runtime, let connection = runtime.connection else {
            if route.owner == .local {
                if !startingIfNeeded { return }
                throw TaskActionRoute.Failure.agentUnavailable(startFailure(of: route.key.agent))
            }
            throw TaskActionRoute.Failure.unavailable
        }
        guard runtime.capabilities?.deleteSessions == true else { return }
        _ = try await connection.send(DeleteSessionRequest(sessionId: route.key.id))
    }

    func startInProjectFolder(using route: TaskActionRoute) async throws {
        if route.owner == .local {
            _ = try await startTask(
                in: route.project.id, folder: route.project.url, title: route.title, agent: route.key.agent)
            return
        }
        _ = try workspaceProvider(for: route)
        guard let runtime = taskRuntime(for: route.owner, agent: route.key.agent) else {
            throw TaskActionRoute.Failure.unavailable
        }
        if !runtime.isReady { await runtime.startOnHost() }
        guard runtime.isReady else { throw TaskActionRoute.Failure.unavailable }
        let session = try await launcher.start(on: runtime, cwd: route.project.url, project: route.project.id)
        rename(session.key, to: route.title)
        session.wantsComposerFocus = true
        selection = session.key
    }

    func deleteWorkspace(using route: TaskActionRoute) async throws {
        try await inWorkspaceOrder(using: route) {
            let provider = try self.workspaceProvider(for: route)
            if let folder = route.workspace {
                try await provider?.deleteWorkspace(at: folder, in: route.project)
            }
            guard !route.isDiscardedDraft else { return }
            // Teardown only follows successful cleanup, including on retry. A failed deletion
            // must leave the workspace and its recovery material available.
            await provider?.taskWasDeleted(
                route.key, title: route.title, folder: route.folder ?? route.project.url, in: route.project)
        }
    }

    func inWorkspaceOrder<Value: Sendable>(
        using route: TaskActionRoute, _ work: @escaping @MainActor () async throws -> Value
    ) async throws -> Value {
        try await inWorkspaceOrder(key: route.orderingKey, work)
    }
}
