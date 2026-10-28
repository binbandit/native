import ACP
import Exec
import Foundation
import Git
import GitHub

@testable import Native

@MainActor
enum SidebarArchivedPullRequestChecks {
    static func run() async throws {
        let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
            .appending(path: "sidebar-archive-\(UUID())")
        let folder = root.appending(path: "project", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        // Git is real but isolated from the person's configuration, hooks and credentials. gh is fake.
        let environment = [
            "PATH": "/usr/bin:/bin", "HOME": root.path, "GIT_CONFIG_NOSYSTEM": "1",
            "GIT_CONFIG_GLOBAL": "/dev/null", "GIT_AUTHOR_NAME": "Fixture", "GIT_COMMITTER_NAME": "Fixture",
            "GIT_AUTHOR_EMAIL": "fixture@example.test", "GIT_COMMITTER_EMAIL": "fixture@example.test",
        ]
        let runner = LocalCommandRunner()
        for arguments in [["init", "-b", "main"], ["commit", "--allow-empty", "-m", "Fixture"]] {
            let result = try await runner.run(Command("git", arguments, in: folder.path, environment: environment))
            try require(result.succeeded, "Fixture git failed: \(result.errorOutput)")
        }
        func store() -> GitStore {
            let store = GitStore(
                environment: { environment }, settings: GitSettings(defaults: PreviewUserDefaults()),
                worktreesFolder: root.appending(path: "worktrees"),
                turnBaselines: GitTurnBaselines(defaults: PreviewUserDefaults())
            ) { Git(environment: $0, runner: runner, monitor: SidebarArchivedPullRequestMonitor()) }
            store.allowsWorktreeFetch = { false }
            return store
        }
        let git = store()
        let github = GitHubModel(
            environment: { _ in [:] }, runner: SidebarArchivedPullRequestRunner(), defaults: PreviewUserDefaults())
        let defaults = PreviewUserDefaults()
        let app = AppModel(
            plugins: PluginRegistry(builtIns: [BuiltInPlugins.claudeCode]), defaults: defaults, catalogURL: nil)
        _ = app.runtimes.sync()
        let project = app.projects.add(folder)
        guard let checkout = try await git.prepareTaskCheckout(in: folder, prefix: "fixture/")?.folder else {
            throw Failure("No managed worktree")
        }
        let info = SessionInfo(sessionId: SessionID("archived-pr"), cwd: checkout.path, title: "Archived pull request")
        let agent = AgentDefinition.ID(rawValue: "claude-code")
        let key = SessionKey(agent: agent, id: info.sessionId)
        app.catalog.add(info, for: agent, in: project.id)
        try require(
            await git.isTaskWorktree(checkout, of: folder), "Fixture must be a managed worktree: \(checkout.path)")
        let workspaces = GitTaskWorkspaceProvider(
            git: git, gitHub: github,
            scripts: TaskScriptCenter(settings: TaskScriptSettings(defaults: PreviewUserDefaults()), runner: runner))
        app.taskWorkspaces = workspaces
        defer { withExtendedLifetime(workspaces) {} }
        guard let summary = app.allSessions(in: project.id).first else { throw Failure("No fixture task") }
        let insights = AppSidebarTaskInsights.make(model: app, git: git, gitHub: github)
        await insights.prepare([summary])
        try require(insights.pullRequestBadge(summary) != nil, "Active worktree must have a PR")
        await app.archiveSession(key)
        try require(app.isArchived(key), "Normal archive must archive the task")
        try require(!FileManager.default.fileExists(atPath: checkout.path), "Normal archive must remove the worktree")
        try require(app.problems.list(for: project.id).isEmpty, "Archive must not report a workspace failure")
        await insights.prepare([summary])
        try require(insights.pullRequestBadge(summary) != nil, "Removed worktree must keep its archived PR badge")

        // A fresh app and git/gh stores have no live checkout or cached PR to conceal the regression.
        let restored = AppModel(
            plugins: PluginRegistry(builtIns: [BuiltInPlugins.claudeCode]), defaults: defaults, catalogURL: nil)
        _ = restored.runtimes.sync()
        restored.catalog.add(info, for: agent, in: project.id)
        try require(restored.isArchived(key), "Archive state must survive app initialization")
        let freshGit = store()
        let freshRunner = SidebarArchivedPullRequestRunner()
        let freshHub = GitHubModel(
            environment: { _ in [:] }, runner: freshRunner, defaults: PreviewUserDefaults())
        var opened: URL?
        freshHub.openExternally = { opened = $0 }
        let freshInsights = AppSidebarTaskInsights.make(model: restored, git: freshGit, gitHub: freshHub)
        await freshInsights.prepare([summary])
        try require(freshInsights.pullRequestBadge(summary) != nil, "Archived PR must resolve after relaunch")
        let branch = AppTaskPullRequests(model: restored, git: freshGit, gitHub: freshHub).branch(of: summary)
        try require(
            branch?.directory == folder && branch?.host == nil, "Archived PR must use the surviving local project")
        let lookups = await freshRunner.commands.filter { $0.arguments.first == "pr" }
        try require(lookups.count == 1, "Archived task must share the PR cache")
        try require(
            lookups.first?.directory == folder.path && lookups.first?.arguments.contains(branch?.branch ?? "") == true,
            "gh must look up the saved branch from the surviving checkout")
        freshInsights.pullRequestMenu(summary)?.items.first { $0.title == "Open on GitHub" }?.perform()
        try require(opened?.lastPathComponent == "107", "Archived row menu must open its own PR")
        ProjectRefreshWiring.connect(model: restored, git: freshGit, gitHub: freshHub)
        await freshRunner.setOpen()
        await restored.refreshProject(project.id)
        try require(
            branch.flatMap { freshHub.pullRequest(for: $0) }?.state == .open,
            "Project Refresh must bypass the archived PR cache")
        try require(
            !FileManager.default.fileExists(atPath: checkout.path), "Looking up a PR must not restore its worktree")
        print("PASS: normal archive removes its worktree; PR badge and menu survive fresh app/git/gh stores")
    }

    private struct Failure: Error { let message: String; init(_ message: String) { self.message = message } }

    private static func require(_ value: Bool, _ message: String) throws {
        if !value { throw Failure(message) }
    }
}

private struct SidebarArchivedPullRequestMonitor: RepositoryMonitor {
    func changes(in repository: Repository) -> AsyncStream<RepositoryChange> { AsyncStream { $0.finish() } }
}

private actor SidebarArchivedPullRequestRunner: CommandRunner {
    private(set) var commands: [Command] = []
    private var state = "MERGED"

    func setOpen() { state = "OPEN" }

    func run(_ command: Command) async throws -> CommandResult {
        commands.append(command)
        let output: String
        if command.arguments.first == "auth" {
            output =
                #"{"hosts":{"github.com":[{"state":"success","active":true,"host":"github.com","login":"fixture"}]}}"#
        } else if command.arguments.first == "api" {
            output = #"{"login":"fixture"}"#
        } else {
            output =
                #"[{"number":107,"title":"Archived pull request","url":"https://github.com/fixture/sidebar/pull/107","state":"\#(state)","isDraft":false,"headRefName":"archived-pull-request","baseRefName":"main","createdAt":"2026-10-01T00:00:00Z","updatedAt":"2026-10-01T00:00:00Z","statusCheckRollup":[]}]"#
        }
        return CommandResult(exitCode: 0, standardOutput: Data(output.utf8), standardError: Data())
    }
}
