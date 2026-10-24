import ACP
import Foundation
import NativeHostClient
import NativeHostProtocol

@testable import Native
@testable import NativeLink

private struct RoutingFailure: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

private actor RoutingHost: HostTransport {
    nonisolated var displayName: String { "Routing fixture" }
    private var peer: JSONRPCPeer?
    var summaries: [HostSessionSummary]
    private(set) var deleted: [SessionID] = []
    var failsDeletion = false

    init(_ ids: [String], folder: String) {
        summaries = ids.map {
            HostSessionSummary(
                id: HostSessionID(), agentID: "fixture", agentName: "Fixture", agentSessionID: SessionID($0),
                cwd: folder, phase: .idle)
        }
    }

    func configure(failsDeletion: Bool) { self.failsDeletion = failsDeletion }
    func clearListing() { summaries = [] }
    func move(_ id: String, to folder: String) {
        if let index = summaries.firstIndex(where: { $0.agentSessionID == SessionID(id) }) {
            summaries[index].cwd = folder
        }
    }

    func connect() async throws -> any ByteStream {
        let (clientEnd, hostEnd) = try UnixSocket.pair()
        let peer = JSONRPCPeer(channel: ByteChannel.socket(hostEnd, label: "routing-host"), label: "routing-host") {
            [weak self] event in
            if case .request(let message) = event {
                Task {
                    do { try await self?.receive(message) } catch {
                        print("FAIL: fixture request: \(error)")
                        exit(1)
                    }
                }
            }
        }
        self.peer = peer
        peer.start()
        return ByteChannel.socket(clientEnd, label: "routing-client")
    }

    private func receive(_ message: JSONRPCPeer.Message) throws {
        guard let id = message.id, let peer else { return }
        switch message.method {
        case HostProtocol.Method.initialize:
            try peer.respond(
                to: id,
                with: HostInfo(
                    protocolVersion: HostProtocol.version, hostID: HostID(), machineName: displayName,
                    hostInfo: PeerInfo(name: "Fixture", version: "1", build: "1"), epoch: UUID(),
                    processID: 1, startedAt: .now, channel: "tests"))
        case HostProtocol.Method.listAgents, HostProtocol.Method.startAgent:
            let initialize: JSONValue = .object([
                "protocolVersion": .number(1),
                "agentCapabilities": .object(["sessionCapabilities": .object(["delete": .object([:])])]),
            ])
            let agent = HostAgent(id: "fixture", name: "Fixture", state: .ready, initialize: initialize)
            if message.method == HostProtocol.Method.listAgents {
                try peer.respond(to: id, with: [agent])
            } else {
                try peer.respond(to: id, with: agent)
            }
        case HostProtocol.Method.listSessions:
            try peer.respond(to: id, with: summaries)
        case HostProtocol.Method.deleteAgentSession:
            let params = try message.params(as: DeleteAgentSessionParams.self)
            deleted.append(params.agentSessionID)
            if failsDeletion {
                try peer.respond(to: id, error: RPCError(code: -32603, message: "Fixture deletion failed"))
            } else {
                try peer.respond(to: id, with: EmptyMessage())
            }
        default:
            try peer.respond(to: id, error: .methodNotFound(message.method))
        }
    }
}

@MainActor
private final class RecordingWorkspaces: TaskWorkspaceProvider {
    struct Call: Equatable {
        let operation: String
        let folder: String
        let project: String
    }
    var calls: [Call] = []
    var failsDeletion = false
    var holdArchive = false
    var pendingArchive: CheckedContinuation<Void, Never>?

    func record(_ operation: String, _ folder: URL, _ project: Project) {
        calls.append(Call(operation: operation, folder: folder.folderPath, project: project.path))
    }
    func workspaceOptions(in project: Project, current: URL) async throws -> [TaskWorkspaceOption] { [] }
    func workspace(for choice: TaskWorkspaceChoice, in project: Project) async throws -> URL { project.url }
    func removeUnusedWorkspace(at folder: URL, in project: Project) async throws -> Bool { false }
    func workspace(forNewTaskIn project: Project, title: String?) async throws -> URL { project.url }
    func newTaskWorkspaceLabel(in project: Project) -> String { "Fixture" }
    func archiveWorkspace(at folder: URL, in project: Project) async throws -> String? {
        record("archive", folder, project)
        if holdArchive { await withCheckedContinuation { pendingArchive = $0 } }
        return "Saved fixture checkpoint."
    }
    func restoreWorkspace(at folder: URL, in project: Project, task: ArchivedTaskDetails?) async throws -> Bool {
        record("restore", folder, project)
        return true
    }
    func restoreRemovedWorkspace(at folder: URL, branch: String, in project: Project) async throws {
        record("restoreRemoved", folder, project)
    }
    func deleteWorkspace(at folder: URL, in project: Project) async throws {
        record("delete", folder, project)
        if failsDeletion { throw RoutingFailure("Fixture workspace is still on disk") }
    }
    func taskWasDeleted(_ task: SessionKey, title: String, folder: URL, in project: Project) async {
        record("deleted", folder, project)
    }
    func taskDidGetTitle(_ title: String, request: String?, workspace: URL, in project: Project) async {}
    func archivedWorkspaceFolders(of project: Project) async -> [URL] { [] }
    func removedWorkspaces(
        among tasks: [(folder: URL, title: String)], in project: Project
    ) async -> [URL: RemovedWorkspace.Fate] { [:] }
    func deleteWorkspaces(of project: Project) async throws {}
    func taskFolders(of project: Project) async -> [URL] { [] }
}

@main
@MainActor
private struct DroidTaskRoutingRegression {
    static func main() async {
        do { try await run() } catch {
            print("FAIL: \(error)")
            exit(1)
        }
    }

    static func require(_ condition: Bool, _ message: String) throws {
        if !condition { throw RoutingFailure(message) }
    }

    static func wait(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(15)
        while !condition() {
            guard ContinuousClock.now < deadline else { throw RoutingFailure("Timed out") }
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    static func run() async throws {
        let scratch = FileManager.default.temporaryDirectory.appending(path: "routing-\(UUID())")
        defer { try? FileManager.default.removeItem(at: scratch) }
        let defaults = PreviewUserDefaults()
        let manifest = PluginManifest(
            id: "fixture", name: "Fixture",
            agents: [
                AgentManifest(id: "fixture", name: "Fixture", command: "/usr/bin/true")
            ])
        let app = AppModel(
            plugins: PluginRegistry(builtIns: [ManifestPlugin(manifest: manifest)], defaults: defaults),
            defaults: defaults, catalogURL: nil,
            hosts: RemoteHosts(store: FilePairedHostStore(directory: scratch.appending(path: "hosts"))))
        _ = app.runtimes.sync()
        let project = app.projects.add(URL(filePath: "/same/repo"))
        let folder = "/same/worktrees/repo/task"
        let local = RecordingWorkspaces()
        let first = RecordingWorkspaces()
        let second = RecordingWorkspaces()
        let devices = DeviceTaskWorkspaces(local: local, model: app)
        app.hosts.deviceWorkspaces = devices
        app.taskWorkspaces = devices
        func key(_ id: String) -> SessionKey { SessionKey(agent: .init(rawValue: "fixture"), id: SessionID(id)) }
        if !app.offersRemoteHosts {
            app.hosts.deviceWorkspaces = nil
            app.taskWorkspaces = local
            let task = key("local")
            app.catalog.add(SessionInfo(sessionId: task.id, cwd: folder), for: task.agent, in: project.id)
            await app.archiveSession(task)
            await app.unarchiveSession(task)
            app.deleteSession(task)
            app.lastUndoable?.undo()
            try require(app.pendingDeletionKeys.isEmpty, "local deletion undo failed")
            let discarded = ProjectProblem(
                project: project.id, work: .workspaceDeletion(key("discarded"), folder: URL(filePath: folder)),
                title: "Fixture", recovery: "Fixture")
            app.problems.report(discarded)
            await app.retry(discarded)
            try require(app.problems.all.isEmpty, "legacy local cleanup retry failed")
            try require(
                local.calls.map(\.operation) == ["archive", "restore", "delete"], "default-off local actions changed")
            print("PASS: default-off local archive, restore, delete undo and discarded-workspace retry")
            return
        }
        func connect(
            _ ids: [String], provider: RecordingWorkspaces
        ) async throws -> (RemoteHost, RoutingHost, NativeHostClient) {
            let transport = RoutingHost(ids, folder: folder)
            let client = NativeHostClient(
                transport: transport, clientInfo: PeerInfo(name: "Fixture", version: "1", build: "1"))
            let paired = PairedHost(
                result: LinkPairingResult(
                    hostID: NativeHostProtocol.HostID(), hostKey: LinkIdentity().publicKey, hostName: "Fixture",
                    deviceID: UUID(), grants: LinkGrants(), addresses: []), identity: LinkIdentity())
            let host = app.hosts.add(paired)
            host.worktreesFolder = "/same/worktrees"
            host.taskWorkspaces = provider
            app.setCheckout(project.path, of: project.id, on: host.id)
            host.start(using: client)
            _ = try await client.connected()
            await host.refresh()
            return (host, transport, client)
        }
        let (firstHost, firstTransport, firstClient) = try await connect(["first"], provider: first)
        let secondConnection = try await connect(
            ["second", "undo", "offline", "delete", "cancel"], provider: second)
        var secondHost = secondConnection.0
        let secondTransport = secondConnection.1
        let secondClient = secondConnection.2
        let localTransport = RoutingHost([], folder: folder)
        let localClient = NativeHostClient(
            transport: localTransport, clientInfo: PeerInfo(name: "Fixture", version: "1", build: "1"))
        await localClient.start()
        _ = try await localClient.connected()
        app.connectHost(client: localClient)
        await app.followHost()
        _ = await app.checkForAgents()
        app.indexRemoteSessions()
        app.catalog.add(SessionInfo(sessionId: key("local").id, cwd: folder), for: key("local").agent, in: project.id)
        await app.archiveSession(key("second"))
        try require(
            second.calls.map(\.operation) == ["archive"], "unopened second-host archive selected another provider")
        try require(first.calls.isEmpty && local.calls.isEmpty, "remote archive touched local or first host")
        await app.unarchiveSession(key("second"))
        try require(second.calls.map(\.operation) == ["archive", "restore"], "restore lost host")
        await app.archiveSessions([key("local"), key("first"), key("second")])
        try require(local.calls.map(\.operation) == ["archive"], "local archive used a remote provider")
        try require(first.calls.map(\.operation) == ["archive"], "bulk archive missed first host")
        try require(
            second.calls.map(\.operation) == ["archive", "restore", "archive"], "bulk archive missed second host")
        await app.unarchiveSessions([key("local"), key("first"), key("second")])
        for provider in [local, first, second] {
            try require(
                provider.calls.allSatisfy { $0.folder == folder && $0.project == project.path },
                "action changed its task folder or checkout")
        }
        local.calls = []; first.calls = []; second.calls = []

        let orphan = key("known-remote-without-owner")
        app.catalog.remote[orphan] = (project.id, SessionInfo(sessionId: orphan.id, cwd: folder))
        await app.archiveSession(orphan)
        try require(
            app.problems.all.contains { $0.work == .workspaceArchive(orphan) },
            "unresolved remote identity silently succeeded")
        try require(app.agentRuntime(for: orphan) == nil, "unresolved remote identity selected local runtime")
        try require(await app.ensureRunning(for: orphan) == nil, "unresolved remote retry started a local agent")
        try require(
            local.calls.isEmpty && first.calls.isEmpty && second.calls.isEmpty,
            "unresolved remote identity selected a provider")

        guard let undoSummary = secondHost.sessions.first(where: { $0.agentSessionID == key("undo").id }),
            let fixtureAgent = app.plugins.agents.first
        else { throw RoutingFailure("Missing open-session fixture") }
        let openTask = SessionModel(
            agent: fixtureAgent, id: key("undo").id, summary: undoSummary, client: secondClient,
            services: app.sessions.services, promptCapabilities: PromptCapabilities(), origin: .user, parent: nil)
        app.sessions.register(openTask)
        second.holdArchive = true
        let archiving = Task { await app.archiveSession(key("undo")) }
        try await wait { second.pendingArchive != nil }
        app.lastUndoable?.undo()
        var localFinished = false
        let localArchive = Task {
            await app.archiveSession(key("local")); localFinished = true
        }
        try await wait { localFinished }
        try require(second.calls.map(\.operation) == ["archive"], "undo restore overtook pending archive")
        second.holdArchive = false
        second.pendingArchive?.resume()
        second.pendingArchive = nil
        await archiving.value
        await localArchive.value
        try await wait { second.calls.count == 2 }
        try require(second.calls.map(\.operation) == ["archive", "restore"], "undo did not restore on same host")
        try require(!app.isArchived(key("undo")), "undo left task archived")
        await app.unarchiveSession(key("local"))
        local.calls = []; first.calls = []; second.calls = []

        app.deleteSessions([key("cancel"), key("second")])
        app.lastUndoable?.undo()
        try require(app.pendingDeletionKeys.isEmpty, "bulk delete undo did not cancel every deletion")

        // Capture both unopened tasks before the listing disappears during the grace period.
        second.failsDeletion = true
        await secondTransport.configure(failsDeletion: true)
        app.deleteSession(key("delete"))
        try require(second.calls.isEmpty, "deletion ran before its undo window")
        secondHost.taskWorkspaces = nil
        secondHost.stop()
        await secondClient.stop()
        await app.archiveSession(key("offline"))
        guard let offline = app.problems.all.first(where: { $0.work == .workspaceArchive(key("offline")) }) else {
            throw RoutingFailure("offline archive did not retain a recoverable problem")
        }
        try require(local.calls.isEmpty && first.calls.isEmpty && second.calls.isEmpty, "offline action fell through")
        await app.retry(offline)
        try require(app.problems.all.contains(where: { $0.id == offline.id }), "offline retry silently succeeded")
        try await wait {
            app.problems.all.contains(where: {
                if case .workspaceDeletion(let task, _) = $0.work { task == key("delete") } else { false }
            })
        }
        guard
            let workspaceProblem = app.problems.all.first(where: {
                if case .workspaceDeletion = $0.work { true } else { false }
            }),
            let agentProblem = app.problems.all.first(where: { $0.work == .agentCopyDeletion(key("delete")) })
        else {
            throw RoutingFailure("failed remote deletion lost its recovery information")
        }
        try require(local.calls.isEmpty && first.calls.isEmpty && second.calls.isEmpty, "offline deletion fell through")
        // A replacement connection has no listing for either task. Recovery must use saved ownership.
        let replacementTransport = RoutingHost([], folder: folder)
        await replacementTransport.configure(failsDeletion: true)
        let replacement = NativeHostClient(
            transport: replacementTransport, clientInfo: PeerInfo(name: "Fixture", version: "1", build: "1"))
        secondHost = app.hosts.add(secondHost.paired)
        secondHost.start(using: replacement)
        _ = try await replacement.connected()
        await secondHost.refresh()
        secondHost.taskWorkspaces = second
        app.indexRemoteSessions()
        await app.retry(offline)
        try require(!app.problems.all.contains(where: { $0.id == offline.id }), "reconnected archive retry failed")
        try require(second.calls.map(\.operation) == ["archive"], "retry did not reach original host")
        secondHost.taskWorkspaces = nil
        await app.unarchiveSession(key("offline"))
        guard let restoreProblem = app.problems.all.first(where: { $0.work == .workspaceRestore(key("offline")) })
        else {
            throw RoutingFailure("offline restore lost recovery after its listing disappeared")
        }
        secondHost.taskWorkspaces = second
        await app.retry(restoreProblem)
        try require(!app.problems.all.contains(where: { $0.id == restoreProblem.id }), "restore retry did not recover")
        await app.retry(agentProblem)
        await app.retry(workspaceProblem)
        try require(
            workspaceProblem.recovery.contains("still on disk") && workspaceProblem.title.contains("New Task"),
            "workspace recovery is inaccurate")
        try require(!second.calls.contains(where: { $0.operation == "deleted" }), "failed deletion ran teardown")
        try require(await replacementTransport.deleted == [key("delete").id], "agent deletion missed owning connection")
        second.failsDeletion = false
        await replacementTransport.configure(failsDeletion: false)
        await app.retry(agentProblem)
        await app.retry(workspaceProblem)
        try require(
            await replacementTransport.deleted == [key("delete").id, key("delete").id],
            "agent retry lost owning connection")
        try require(
            second.calls.map(\.operation) == ["archive", "restore", "delete", "delete", "deleted"],
            "workspace retry lost original route")
        try require(local.calls.isEmpty && first.calls.isEmpty, "delete or retry touched another machine")
        let firstDeleted = await firstTransport.deleted
        let retiredDeleted = await secondTransport.deleted
        try require(firstDeleted.isEmpty && retiredDeleted.isEmpty, "agent deletion used another or retired connection")

        // A different remote project root is protected even though it differs from this Mac's.
        let rootProject = app.projects.add(URL(filePath: "/local/project-root"))
        let rootTransport = RoutingHost(
            ["remote-root", "remote-worktree", "no-provider-root"], folder: "/remote/project-root")
        let remoteWorktree = "/remote/worktrees/project-root/task"
        await rootTransport.move("remote-worktree", to: remoteWorktree)
        let rootClient = NativeHostClient(
            transport: rootTransport, clientInfo: PeerInfo(name: "Fixture", version: "1", build: "1"))
        secondHost.stop()
        await replacement.stop()
        secondHost = app.hosts.add(secondHost.paired)
        secondHost.taskWorkspaces = second
        secondHost.worktreesFolder = "/remote/worktrees"
        secondHost.start(using: rootClient)
        _ = try await rootClient.connected()
        await secondHost.refresh()
        app.setCheckout("/remote/project-root", of: rootProject.id, on: secondHost.id)
        app.indexRemoteSessions()
        second.calls = []
        await app.archiveSession(key("remote-worktree"))
        await app.unarchiveSession(key("remote-worktree"))
        try require(
            second.calls == [
                .init(operation: "archive", folder: remoteWorktree, project: "/remote/project-root"),
                .init(operation: "restore", folder: remoteWorktree, project: "/remote/project-root"),
            ], "remote worktree used the local project root")
        second.calls = []
        await app.archiveSession(key("remote-root"))
        await app.unarchiveSession(key("remote-root"))
        app.deleteSession(key("remote-root"))
        try await wait { second.calls.contains(where: { $0.operation == "deleted" }) }
        try require(second.calls.map(\.operation) == ["deleted"], "remote project root was treated as a worktree")
        try require(second.calls.first?.project == "/remote/project-root", "teardown used the local checkout")
        try require(local.calls.isEmpty && first.calls.isEmpty, "root cleanup touched another machine")
        #if !BEFORE
        secondHost.taskWorkspaces = nil
        try require(!secondHost.paired.grants.runCommands, "fixture unexpectedly grants command execution")
        await app.archiveSession(key("no-provider-root"))
        await app.unarchiveSession(key("no-provider-root"))
        try require(
            !app.problems.all.contains {
                $0.work == .workspaceArchive(key("no-provider-root"))
                    || $0.work == .workspaceRestore(key("no-provider-root"))
            }, "checkout-root task required a workspace provider")
        guard let rootRoute = app.taskActionRoute(for: key("no-provider-root")) else {
            throw RoutingFailure("Missing checkout-root route")
        }
        try await app.deleteWorkspace(using: rootRoute)
        try require(local.calls.isEmpty && first.calls.isEmpty, "provider-free root cleanup reached another host")
        #endif
        try require(await localTransport.deleted.isEmpty, "remote deletion reached local agent")
        await localClient.stop()
        await rootClient.stop()
        _ = firstHost
        await firstClient.stop()
        await secondClient.stop()
        print("PASS: task actions keep host identity with colliding paths")
    }
}
