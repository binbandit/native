import ACP
import Exec
import Foundation
import Git
import NativeHostClient
import NativeHostProtocol
import TaskScripts

@testable import Native
@testable import NativeLink

@main
@MainActor
private struct TaskWorkspaceRegression {
    static func main() async throws {
        let scratch = FileManager.default.temporaryDirectory.appending(path: "task-workspace-\(UUID())")
        let folder = scratch.appending(path: "project")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: scratch) }
        let host = WorkspaceTestHost()
        let client = NativeHostClient(transport: host, clientInfo: PeerInfo(name: "tests", version: "1", build: "1"))
        await client.start()
        _ = try await client.connected()
        let defaults = PreviewUserDefaults()
        let manifest = PluginManifest(
            id: "workspace-fixture", name: "Fixture",
            agents: [
                AgentManifest(id: "workspace-fake", name: "Fixture", command: "/usr/bin/true")
            ])
        let app = AppModel(
            plugins: PluginRegistry(builtIns: [ManifestPlugin(manifest: manifest)], defaults: defaults),
            defaults: defaults, catalogURL: scratch.appending(path: "catalog.json"),
            hosts: RemoteHosts(store: FilePairedHostStore(directory: scratch.appending(path: "hosts"))))
        app.connectHost(client: client)
        await app.followHost()
        _ = await app.checkForAgents()
        let runner = LocalCommandRunner()
        var environment = ProcessInfo.processInfo.environment
        environment.merge([
            "GIT_CONFIG_GLOBAL": "/dev/null", "GIT_CONFIG_NOSYSTEM": "1",
            "GIT_AUTHOR_NAME": "Fixture", "GIT_AUTHOR_EMAIL": "fixture@example.com",
            "GIT_COMMITTER_NAME": "Fixture", "GIT_COMMITTER_EMAIL": "fixture@example.com",
        ]) { $1 }
        for arguments in [
            ["init", "--quiet", "--initial-branch=main"],
            ["commit", "--quiet", "--allow-empty", "-m", "Initial"], ["branch", "feature"],
        ] {
            let result = try await runner.run(Command("git", arguments, in: folder.path(), environment: environment))
            try check(result.succeeded, "fixture git succeeds")
        }
        let settings = GitSettings(defaults: defaults)
        settings.branchPrefixMode = .none
        let git = GitStore(
            environment: { environment }, settings: settings,
            worktreesFolder: scratch.appending(path: "worktrees"), makeGit: { Git(environment: $0) })
        git.allowsWorktreeFetch = { false }
        let scripts = TaskScriptCenter(settings: TaskScriptSettings(defaults: defaults), runner: runner)
        let github = GitHubModel(environment: { _ in environment }, runner: runner, defaults: defaults)
        let provider = GitTaskWorkspaceProvider(git: git, gitHub: github, scripts: scripts)
        app.taskWorkspaces = provider
        let project = app.projects.add(folder)
        let agent = AgentDefinition.ID(rawValue: "workspace-fake")
        guard let runtime = await app.ensureRunning(agent) else { throw Failure("fixture agent is ready") }
        func start(at cwd: URL) async throws -> SessionModel {
            let task = try await app.launcher.start(on: runtime, cwd: cwd, project: project.id)
            app.catalog.add(
                SessionInfo(sessionId: task.id, cwd: cwd.path(), updatedAt: .now), for: agent, in: project.id)
            app.unsentSessions.started(task.key)
            app.selection = task.key
            return task
        }
        let oldFolder = try await provider.workspace(forNewTaskIn: project, title: nil)
        let source = try await start(at: oldFolder)
        source.draft = "Keep the draft"
        let attachment = PromptAttachment(
            url: scratch.appending(path: "notes.txt"), content: .text("Fixture"), byteCount: 7)
        source.attachments = [attachment]
        app.titles.rename(source.titleKey, to: "Chosen title")
        app.ordering.pin(source.key)
        guard let modelOption = source.configOptions.first else { throw Failure("host config arrived") }
        await source.setConfigOption(modelOption, to: "large")
        let choices = try await app.workspaceOptions(for: source)
        try check(choices.contains { $0.choice == .branch("feature") }, "local branches are offered")
        try check(choices.contains { $0.isCurrent }, "current checkout is identified")
        let command = NativeCommand.composer.first { $0.id.rawValue == "session.changeWorkspace" }
        try check(command?.isAvailable(CommandContext(session: source)) == true, "Task menu offers workspace change")
        command?.perform(CommandContext(session: source))
        try check(source.isWorkspacePickerRequested, "menu opens the picker through the model")
        source.addNotice("The task is ready in its workspace.", isError: false)
        try check(!source.isTranscriptEmpty && source.canChangeWorkspace, "notice-only tasks remain eligible")
        source.isWorkspacePickerRequested = false
        command?.perform(CommandContext(session: source))
        try check(source.isWorkspacePickerRequested, "notice-only task can request the workspace picker")
        let target = try await app.changeWorkspace(of: source, to: .branch("feature"))
        try check(
            target.draft == "Keep the draft" && target.attachments == [attachment], "draft and attachment survive")
        try check(target.displayTitle == "Chosen title" && app.ordering.isPinned(target.key), "title and pin survive")
        try check(app.selection == target.key && app.session(source.key) == nil, "replacement takes the task's place")
        try check(!FileManager.default.fileExists(atPath: oldFolder.path()), "untouched worktree is removed")
        try check(await host.closed.contains(source.host?.id ?? HostSessionID()), "old agent conversation is closed")
        try check(
            await host.configChanges.contains { $0.sessionID == target.host?.id && $0.value == "large" },
            "model choice restored on replacement")
        let repository = try await git.requireRepository(at: folder)
        try check(try await repository.status().branch.name == "main", "project branch stays unchanged")
        try check(
            try await git.requireRepository(at: target.cwd).status().branch.name == "feature", "chosen branch is used")
        do {
            _ = try await source.submit("stale", .queue)
            throw Failure("retired conversation accepted a message")
        } catch is SessionModel.SendError {}
        let checkout = target.cwd
        let inProject = try await app.changeWorkspace(of: target, to: .project)
        try check(SessionFolder.isSame(inProject.cwd.path(), folder.path()), "project folder is selectable")
        try check(!FileManager.default.fileExists(atPath: checkout.path()), "second unused checkout is cleaned")
        try check(try await repository.hasBranch("feature"), "existing branch is retained")
        settings.newTaskWorkspace = .branch
        let inNewTree = try await app.changeWorkspace(of: inProject, to: .newWorktree)
        try check(
            !SessionFolder.isSame(inNewTree.cwd.path(), folder.path()), "explicit worktree overrides branch default")
        try check(try await repository.status().branch.name == "main", "new worktree leaves project branch unchanged")
        app.workspaceChangeBlock = { _ in "Close the task's terminal tabs first." }
        do {
            _ = try await app.changeWorkspace(of: inNewTree, to: .project); throw Failure("busy folder moved")
        } catch is TaskWorkspaceSelectionError {}
        try check(
            inNewTree.canChangeWorkspace && inNewTree.draft == "Keep the draft",
            "active folder work blocks replacement without losing the draft")
        app.workspaceChangeBlock = { _ in nil }

        // A failed replacement must leave the old task and its draft intact and remove the unused candidate.
        let countBeforeFailure = try await repository.worktrees().count
        await host.configure(fail: true)
        do {
            _ = try await app.changeWorkspace(of: inNewTree, to: .newWorktree)
            throw Failure("preparation failure was ignored")
        } catch is Failure { throw Failure("preparation failure was ignored") } catch {}
        try check(
            inNewTree.canChangeWorkspace && app.session(inNewTree.key) === inNewTree, "failure releases the old task")
        try check(inNewTree.draft == "Keep the draft", "failed preparation keeps draft")
        try check(
            try await repository.worktrees().count == countBeforeFailure, "failed replacement leaves no unused worktree"
        )

        // Hold session/new at the wire: both composer sends and API sends must be refused before any await.
        await host.configure()
        let waiting = try await start(at: folder)
        let previousBranch = try await git.requireRepository(at: inNewTree.cwd).status().branch.name
        guard let previousBranch else { throw Failure("task branch exists") }
        await host.configure(hold: true)
        let moving = Task { try await app.changeWorkspace(of: inNewTree, to: .newWorktree) }
        try await wait { await host.hasPendingNew }
        let following = Task { try await app.changeWorkspace(of: waiting, to: .branch(previousBranch)) }
        await inNewTree.submit(.queue)
        try check(inNewTree.draft == "Keep the draft", "composer keeps the draft while moving")
        do {
            _ = try await inNewTree.submit("racing send", .queue); throw Failure("send raced workspace change")
        } catch is SessionModel.SendError {}
        try check(await host.prompts.isEmpty, "no message sent during workspace change")
        try await host.releaseNew()
        let moved = try await moving.value
        let followed = try await following.value
        try check(
            FileManager.default.fileExists(atPath: followed.cwd.path()),
            "concurrent selection cannot reuse a checkout being removed")
        try check(
            try await git.requireRepository(at: followed.cwd).status().branch.name == previousBranch,
            "concurrent selection keeps the chosen branch")
        try check(moved.canChangeWorkspace, "replacement remains editable until first message")

        // A queued first message locks the folder even if it is removed before delivery.
        app.sessions.services.sendGate.setWorkspaceHold("fixture hold", for: moved.cwd)
        _ = try await moved.submit("queued first message", .queue)
        try check(!moved.canChangeWorkspace && moved.hasQueuedPrompts, "queued first message locks workspace")
        moved.heldPrompts.removeAll()
        try check(!moved.canChangeWorkspace, "removing queue does not reopen the workspace")
        do {
            _ = try await app.changeWorkspace(of: moved, to: .project); throw Failure("sent task moved")
        } catch is TaskWorkspaceSelectionError {}
        try check(
            command?.isAvailable(CommandContext(session: moved)) == false, "menu is disabled after first submission")

        // A real accepted host request with no echo yet also locks the folder.
        let sent = try await start(at: folder)
        _ = try await sent.submit("first message", .queue)
        try check(!sent.canChangeWorkspace && sent.isTranscriptEmpty, "accepted prompt locks before transcript echo")
        let cleared = try await start(at: folder)
        app.earlierConversations.record(cleared.key, after: sent.key)
        try check(!cleared.canChangeWorkspace, "clear conversation does not unlock an established task")

        // Reusing user-owned worktrees must not make them cleanup candidates.
        let ownedFolder = scratch.appending(path: "user-worktree")
        _ = try await repository.addWorktree(at: ownedFolder, newBranch: "user-owned")
        let blank = try await start(at: folder)
        let reused = try await app.changeWorkspace(of: blank, to: .branch("user-owned"))
        try check(SessionFolder.isSame(reused.cwd.path(), ownedFolder.path()), "checked-out branch reuses its folder")
        _ = try await app.changeWorkspace(of: reused, to: .project)
        try check(FileManager.default.fileExists(atPath: ownedFolder.path()), "user-owned worktree is preserved")
        let sharedTree = try await provider.workspace(for: .newWorktree, in: project)
        let shared = try await start(at: sharedTree)
        _ = try await start(at: sharedTree)
        _ = try await app.changeWorkspace(of: shared, to: .project)
        try check(
            FileManager.default.fileExists(atPath: sharedTree.path()), "worktree shared by another task is preserved")
        let pinnedTree = try await provider.workspace(for: .newWorktree, in: project)
        let pinned = try await start(at: pinnedTree)
        app.ordering.pin(pinned.key)
        app.sessions.remove(pinned)
        guard let pinnedBranch = try await git.requireRepository(at: pinnedTree).status().branch.name else {
            throw Failure("pinned task branch exists")
        }
        let visitor = try await start(at: folder)
        let visiting = try await app.changeWorkspace(of: visitor, to: .branch(pinnedBranch))
        _ = try await app.changeWorkspace(of: visiting, to: .project)
        try check(
            FileManager.default.fileExists(atPath: pinnedTree.path()),
            "unopened pinned owner preserves its task worktree")
        let warningSource = try await start(at: pinnedTree)
        await host.configure(failClose: true)
        let warned = try await app.changeWorkspace(of: warningSource, to: .project)
        try check(!warned.isTranscriptEmpty && warned.canChangeWorkspace, "close warning keeps workspace editable")
        command?.perform(CommandContext(session: warned))
        try check(warned.isWorkspacePickerRequested, "close warning keeps the Task menu action available")
        await host.configure()
        try await remoteReplacement(
            app: app, provider: provider, project: project, scratch: scratch, localHost: host, defaults: defaults)
        await client.stop()
        print(
            "PASS: workspace choices, replacement, cleanup, draft/settings, failures, send races and first-message lock"
        )
    }

    private static func remoteReplacement(
        app: AppModel, provider: GitTaskWorkspaceProvider, project: Project, scratch: URL, localHost: WorkspaceTestHost,
        defaults: UserDefaults
    ) async throws {
        let transport = WorkspaceTestHost(idPrefix: "remote")
        let client = NativeHostClient(
            transport: transport, clientInfo: PeerInfo(name: "tests", version: "1", build: "1"))
        let pairing = PairedHost(
            result: LinkPairingResult(
                hostID: NativeHostProtocol.HostID(), hostKey: LinkIdentity().publicKey, hostName: "Fixture host",
                deviceID: UUID(), grants: LinkGrants(), addresses: []), identity: LinkIdentity())
        let remote = app.hosts.add(pairing)
        remote.taskWorkspaces = provider
        remote.worktreesFolder = scratch.appending(path: "worktrees").path()
        app.setCheckout(project.path, of: project.id, on: remote.id)
        app.launcher.isRemote = { $0 === client }
        remote.onEvent = { _, event in
            app.sessions.handle(event)
            app.indexRemoteSessions()
        }
        remote.start(using: client)
        _ = try await client.connected()
        await remote.refresh()
        guard let runtime = remote.runtime(AgentDefinition.ID(rawValue: "workspace-fake")) else {
            throw Failure("paired fixture agent is ready")
        }
        let source = try await app.launcher.start(on: runtime, cwd: project.url, project: project.id)
        source.draft = "Keep the remote draft"
        let inWorktree = try await app.changeWorkspace(of: source, to: .newWorktree)
        let target = try await app.changeWorkspace(of: inWorktree, to: .branch("user-owned"))
        try check(target.host?.client === client && target.draft == source.draft, "replacement stays on its host")
        try check(
            app.allSessions(in: project.id).filter { $0.id == target.key }.count == 1, "remote task is listed once")
        try check(app.catalog.remote[target.key] != nil, "remote replacement is indexed by its host")
        app.indexRemoteSessions()
        try check(app.catalog.lookup(target.key)?.project == project.id, "index refresh retains a user-owned checkout")
        _ = try await app.workspaceOptions(for: target)
        let savedProjects = Projects(defaults: defaults)
        try check(
            savedProjects.project(project.id)?.checkouts.first(where: { $0.host == remote.id })?.taskFolders?
                .contains(target.cwd.folderPath) == true,
            "remote checkout association survives relaunch")
        try check(
            !app.catalog.sessions(in: project.id, of: target.agent.id).contains { $0.sessionId == target.id },
            "remote replacement stays out of the local catalog")
        try check(!app.unsentSessions.contains(target.key), "remote draft cannot reopen through the local agent")
        app.unsentSessions.keepDrafts { app.sessions.session($0)?.draft }
        remote.stop()
        await client.stop()
        let reloaded = AppModel(
            plugins: app.plugins, defaults: PreviewUserDefaults(), catalogURL: scratch.appending(path: "catalog.json"),
            hosts: RemoteHosts(store: FilePairedHostStore(directory: scratch.appending(path: "offline-hosts"))))
        if let localClient = app.runtimes.host {
            reloaded.connectHost(client: localClient)
            await reloaded.followHost()
            _ = await reloaded.checkForAgents()
        }
        let count = await localHost.newSessionCount
        await reloaded.loadSession(target.key)
        try check(reloaded.catalog.lookup(target.key) == nil, "offline relaunch has no local copy of the remote task")
        try check(await localHost.newSessionCount == count, "offline relaunch never starts a remote task locally")
    }

    private static func check(_ condition: Bool, _ message: String) throws {
        guard condition else { throw Failure(message) }
    }

    private static func wait(_ condition: () async -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(10)
        while !(await condition()) {
            guard ContinuousClock.now < deadline else { throw Failure("Timed out waiting for replacement") }
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    private struct Failure: Error, CustomStringConvertible {
        let description: String
        init(_ description: String) { self.description = description }
    }
}
