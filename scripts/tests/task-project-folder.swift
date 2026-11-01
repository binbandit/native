import ACP
import Exec
import Experiments
import Foundation
import Git

@testable import Native

@MainActor
enum TaskProjectFolderChecks {
    static func run(
        app: AppModel, provider: GitTaskWorkspaceProvider, git: GitStore, experiments: ExperimentStore,
        agent: AgentDefinition.ID, folder: URL, scratch: URL, runner: LocalCommandRunner,
        environment: [String: String]
    ) async throws {
        let namingFolder = scratch.appending(path: "branch-naming")
        let clone = try await runner.run(
            Command(
                "git", ["clone", "--quiet", "--local", folder.path(), namingFolder.path()], environment: environment))
        try require(clone.succeeded, "branch naming fixture cloned")
        let project = app.projects.add(namingFolder)
        let repository = try await git.requireRepository(at: namingFolder)
        git.settings.newTaskWorkspace = .branch
        experiments.set(false, for: .projectFolderTasks)
        await app.newSession(in: project.id, with: agent)
        guard let legacyKey = app.selection, let legacy = app.session(legacyKey) else {
            throw Failure("branch-mode task did not open")
        }
        let provisional = try await repository.status().branch.name
        experiments.set(true, for: .projectFolderTasks)
        app.rememberTaskWorkspace(.project, in: project.id)
        await app.newSession(in: project.id, with: agent)
        guard let borrower = app.selection else { throw Failure("project-folder task did not open") }
        await app.workspaceGotTitle(AppModel.TitleEvent(key: borrower, folder: namingFolder, title: "Keep the branch"))
        try require(try await repository.status().branch.name == provisional, "borrowed provisional branch stays named")
        experiments.set(false, for: .projectFolderTasks)
        await app.workspaceGotTitle(
            AppModel.TitleEvent(key: legacy.key, folder: namingFolder, title: "Name the branch"))
        try require(
            try await repository.status().branch.name == "name-the-branch",
            "legacy branch mode still names its own branch with Labs off")
        experiments.set(true, for: .projectFolderTasks)

        app.quickEntry.enabled = { true }
        app.quickEntry.agent = agent
        app.quickEntry.device = .thisMac
        for unborn in [false, true] {
            let path = scratch.appending(path: unborn ? "unborn" : "plain")
            try FileManager.default.createDirectory(at: path, withIntermediateDirectories: true)
            if unborn {
                let initialized = try await runner.run(
                    Command(
                        "git", ["init", "--quiet", "--initial-branch=main"], in: path.path(), environment: environment))
                try require(initialized.succeeded, "unborn fixture initialized")
            }
            let plain = app.projects.add(path)
            let options = try await provider.workspaceOptions(in: plain, current: path)
            try require(!options.contains { $0.choice == .newWorktree }, "unsupported new folders are omitted")
            app.quickEntry.project = plain.id
            await app.readComposeWorkspaces()
            app.chooseComposeWorkspace(.newWorktree)
            try require(app.composeTask.workspace == .project, "Compose refuses an unsupported separate folder")
            try require(app.preferredTaskWorkspace(in: plain.id) == nil, "unsupported choices are never remembered")
            app.chooseComposeWorkspace(.project)
            await app.newSession(in: plain.id, with: agent)
            let classicFolder = app.selection.flatMap(app.session)?.cwd.path() ?? ""
            try require(SessionFolder.isSame(classicFolder, path.path()), "classic starts in the existing folder")
            app.prepareComposeEditor()
            try await submit(app, text: "Folder fixture")
            if unborn {
                try require(
                    try await git.requireRepository(at: path).status().branch.name == "main",
                    "unborn project keeps its current branch")
            }
        }

        // Temporary isolation for two recipients must not replace the remembered single-task choice.
        let second = AgentDefinition.ID(rawValue: "workspace-second")
        _ = await app.ensureRunning(second)
        app.quickEntry.project = project.id
        await app.readComposeWorkspaces()
        app.prepareComposeEditor()
        app.addComposeAgent(second)
        try require(app.composeTask.second != nil, "second fixture agent is offered")
        try await submit(app, text: "Two recipients")
        try require(app.preferredTaskWorkspace(in: project.id) == .project, "two recipients keep the saved choice")
        await app.readComposeWorkspaces()
        try require(app.composeTask.workspace == .project, "next single task restores the saved project folder")

        // Starting with the automatic default is not an explicit project override.
        let fresh = app.projects.add(scratch.appending(path: "fresh-default"))
        try FileManager.default.createDirectory(at: fresh.url, withIntermediateDirectories: true)
        app.quickEntry.project = fresh.id
        await app.readComposeWorkspaces()
        app.prepareComposeEditor()
        try await submit(app, text: "Automatic default")
        try require(app.preferredTaskWorkspace(in: fresh.id) == nil, "automatic defaults do not create overrides")
    }

    private static func submit(_ app: AppModel, text: String) async throws {
        app.composeTask.editor?.draft = text
        app.startComposeTask(revealing: false)
        guard let task = app.composeTask.starting else { throw Failure("Compose did not start") }
        let pair = app.taskPairs.pair(containing: task.id)
        let partner = pair?.other(than: task.id).flatMap(app.startingTask)
        let deadline = ContinuousClock.now + .seconds(15)
        while task.openedSession == nil || (partner != nil && partner?.openedSession == nil) {
            guard task.failure == nil, partner?.failure == nil, ContinuousClock.now < deadline else {
                throw Failure("Compose fixture failed to open")
            }
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    private static func require(_ condition: Bool, _ message: String) throws {
        if !condition { throw Failure(message) }
    }

    private struct Failure: Error {
        let message: String
        init(_ message: String) { self.message = message }
    }
}
