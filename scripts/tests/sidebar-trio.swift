import ACP
import Exec
import Foundation
import Git
import GitHub
import NativePolicy

@testable import Native

/// Only the injected runner answers these requests; no GitHub credentials or network are used.
private actor SidebarRefreshRunner: CommandRunner {
    var requests = 0
    var fails = false
    var installed = true
    var blocked: CheckedContinuation<Void, Never>?
    var shouldBlock = false

    func setFailure(_ value: Bool) { fails = value }
    func setInstalled(_ value: Bool) { installed = value }
    func blockNext() { shouldBlock = true }
    func release() { blocked?.resume(); blocked = nil }

    func run(_ command: Command) async throws -> CommandResult {
        if !installed { throw CommandError.notFound("gh") }
        if command.arguments.first == "auth" {
            let state = fails ? "error" : "success"
            let output =
                "{\"hosts\":{\"github.com\":[{\"state\":\"\(state)\",\"active\":true,\"host\":\"github.com\",\"login\":\"fixture\",\"tokenSource\":\"keyring\"}]}}"
            return CommandResult(exitCode: fails ? 1 : 0, standardOutput: Data(output.utf8), standardError: Data())
        }
        if command.arguments.first == "api" {
            return CommandResult(
                exitCode: 0, standardOutput: Data("{\"login\":\"fixture\"}".utf8), standardError: Data())
        }
        requests += 1
        if shouldBlock {
            shouldBlock = false
            await withCheckedContinuation { blocked = $0 }
        }
        return CommandResult(
            exitCode: fails ? 4 : 0,
            standardOutput: Data("[]".utf8),
            standardError: fails ? Data("Please run gh auth login".utf8) : Data())
    }
}

private actor SidebarGitRunner: CommandRunner {
    var scans = 0
    var fails = false
    var branch = "before"
    func configure(fails: Bool, branch: String = "after") { self.fails = fails; self.branch = branch }

    func run(_ command: Command) async throws -> CommandResult {
        let output: String
        switch command.arguments.first {
        case "rev-parse":
            let folder = command.directory ?? "/fixture"
            output = "\(folder)\n\(folder)/.git\n\(folder)/.git\n"
        case "status":
            scans += 1
            if fails {
                return CommandResult(exitCode: 1, standardOutput: Data(), standardError: Data("permission denied".utf8))
            }
            output = "# branch.oid abc123\0# branch.head \(branch)\0"
        case "remote": output = "origin\n"
        default: output = ""
        }
        return CommandResult(exitCode: 0, standardOutput: Data(output.utf8), standardError: Data())
    }
}

private struct SidebarNoMonitor: RepositoryMonitor {
    func changes(in repository: Repository) -> AsyncStream<RepositoryChange> { AsyncStream { $0.finish() } }
}

@main
@MainActor
private struct SidebarTrioRegression {
    static var failures = 0

    static func expect(_ result: Bool, _ message: String) {
        if !result { print("FAIL: \(message)"); failures += 1 }
    }

    static func main() async {
        managedFooter()
        await modelActions()
        await branchRefreshes()
        await wiredRefresh()
        let unavailable = GitRepositoryModel(unavailableFolder: URL(filePath: "/fixture/remote"))
        await unavailable.refreshNow()
        expect(unavailable.refreshFailure?.contains("Reconnect") == true, "Unavailable hosts explain recovery")
        if failures > 0 { exit(1) }
        print("PASS: archive groups, full project scope, refresh gating, Retry, cache bypass and in-flight lookup")
    }

    static func managedFooter() {
        let source = StaticPolicySource(managed: [
            PolicyKey.organizationName.rawValue: "Northwind Federal IT",
            PolicyKey.organizationContact.rawValue: "#it-help",
            PolicyKey.remoteHostsEnabled.rawValue: false,
            PolicyKey.companionEnabled.rawValue: false,
        ])
        let center = PolicyCenter(source: source)
        expect(
            center.managementLine == "Managed by Northwind Federal IT · #it-help",
            "Footer names the policy's organization and contact")
        expect(center.policy.organizationContact == "#it-help", "Footer contact comes from policy")
        expect(
            SidebarManagedDetails.facts(center).map(\.name) == ["Other Macs", "Pairing"],
            "Footer describes the two managed restrictions without inventing an account restriction")
        let local = PolicyCenter(source: StaticPolicySource(user: [PolicyKey.remoteHostsEnabled.rawValue: false]))
        expect(SidebarManagedDetails.facts(local).isEmpty, "A personal preference is never called off by policy")
        let enabled = PolicyCenter(source: StaticPolicySource(managed: [PolicyKey.remoteHostsEnabled.rawValue: true]))
        expect(SidebarManagedDetails.facts(enabled).isEmpty, "A managed enabled capability is never called off")
        print("PASS: managed footer restrictions, organization, contact and personal preferences")
    }

    static func modelActions() async {
        let model = AppModel.preview()
        guard let first = model.previewProject(), let second = model.previewProject(1),
            let task = model.allSessions(in: second.id).first
        else { expect(false, "Preview projects exist"); return }
        model.archivedSessions.set(task.id, archived: true)
        model.moveProjects(fromOffsets: IndexSet(integer: 1), toOffset: 0)
        expect(model.archivedTaskGroups.map(\.id) == [second.id, first.id], "Archive follows project reordering")
        model.focusProject(first.id)
        if let pinned = model.sessions(in: first.id).first { model.ordering.pin(pinned.id) }
        let expected = Set(model.allSessions(in: first.id).map(\.id))
        var received = Set<SessionKey>()
        var calls = 0
        var finish: CheckedContinuation<Void, Never>?
        model.refreshProjectState = { project, summaries in
            expect(project.id == first.id, "Refresh uses requested project")
            received = Set(summaries.map(\.id))
            calls += 1
            await withCheckedContinuation { finish = $0 }
            return ["Fixture failure. Reconnect and retry."]
        }
        let command = NativeCommand.projectRefresh(model: model)
        expect(command.isAvailable(CommandContext()), "Refresh command is available")
        let running = Task { await model.refreshProject(first.id) }
        while finish == nil { await Task.yield() }
        expect(model.refreshingProjects.contains(first.id), "Project shows progress until work finishes")
        expect(!command.isAvailable(CommandContext()), "Command is disabled during refresh")
        await model.refreshProject(first.id)
        expect(calls == 1, "Repeated Refresh coalesces")
        expect(received == expected, "Refresh includes archived and hidden tasks")
        finish?.resume()
        await running.value
        expect(model.refreshingProjects.isEmpty, "Progress ends on failure")
        guard let problem = model.problems.list(for: first.id).first else {
            expect(false, "Failure is visible with project"); return
        }
        expect(problem.work == .refresh && problem.suggestion != nil, "Failure offers recovery and Retry")
        model.refreshProjectState = { _, _ in [] }
        await model.retry(problem)
        expect(model.problems.list(for: first.id).isEmpty, "Successful Retry clears the failure")
        expect(model.currentProject?.id == first.id, "Refresh preserves selection")
        model.refreshProjectState = { [weak model] project, _ in
            model?.projects.remove(project.id)
            return ["Failure after removal"]
        }
        await model.refreshProject(first.id)
        expect(model.problems.list(for: first.id).isEmpty, "Removed projects do not retain late failures")
    }

    static func wiredRefresh() async {
        let folder = FileManager.default.temporaryDirectory.appending(
            path: "sidebar-trio-\(UUID().uuidString)", directoryHint: .isDirectory)
        do { try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true) } catch {
            expect(false, "Fixture folder exists"); return
        }
        defer { try? FileManager.default.removeItem(at: folder) }
        let model = AppModel.preview(.empty)
        let project = model.projects.add(folder)
        guard let agent = model.agents.first?.agent.id else { expect(false, "Fixture agent exists"); return }
        for index in 0..<3 {
            let id = SessionID("task-\(index)")
            model.catalog.add(
                SessionInfo(sessionId: id, cwd: folder.path, title: "Task \(index)"),
                for: agent, in: project.id)
            let key = SessionKey(agent: agent, id: id)
            if index == 0 { model.ordering.pin(key) }
            if index == 1 { model.archivedSessions.set(key, archived: true) }
        }
        let runner = SidebarGitRunner()
        let git = GitStore(environment: { [:] }, turnBaselines: GitTurnBaselines(defaults: PreviewUserDefaults())) {
            _ in
            Git(environment: [:], runner: runner, monitor: SidebarNoMonitor())
        }
        let ghRunner = SidebarRefreshRunner()
        let github = GitHubModel(environment: { _ in [:] }, runner: ghRunner, defaults: PreviewUserDefaults())
        ProjectRefreshWiring.connect(model: model, git: git, gitHub: github)
        let repository = git.model(for: folder)
        await repository.refreshNow()
        let before = await runner.scans
        await runner.configure(fails: false)
        await model.refreshProject(project.id)
        expect(await runner.scans == before + 1, "Shared checkout is scanned once for all tasks")
        expect(await ghRunner.requests == 1, "Shared branch is fetched once")
        expect(repository.branch?.name == "after", "Refresh updates live git state")
        await runner.configure(fails: true)
        await model.refreshProject(project.id)
        expect(repository.branch?.name == "after", "Git failure retains last good state")
        expect(repository.refreshFailure != nil, "Git failure after success is reported")
        guard let failure = model.problems.list(for: project.id).first else {
            expect(false, "Git failure reaches project row"); return
        }
        await runner.configure(fails: false)
        await model.retry(failure)
        expect(model.problems.list(for: project.id).isEmpty, "Retry goes through git and clears the project failure")
        expect(repository.refreshFailure == nil, "Successful git read clears stale failure")
    }

    static func branchRefreshes() async {
        let runner = SidebarRefreshRunner()
        let model = GitHubModel(environment: { _ in [:] }, runner: runner, defaults: PreviewUserDefaults())
        let branch = BranchReference(directory: URL(filePath: "/fixture/project"), branch: "feature/task")
        let first = await model.loadPullRequest(for: branch)
        expect(first == nil, "Initial empty pull-request lookup succeeds")
        let count = await runner.requests
        _ = await model.loadPullRequest(for: branch)
        expect(await runner.requests == count, "Background lookup respects cache")
        let old = PullRequestPreviewFixtures.summary(
            "fixture/project", 7, "Task pull request", branch: "feature/task", minutesAgo: 5, author: "fixture")
        model.branchPullRequests[branch] = BranchPullRequest(pullRequest: old, fetchedAt: .distantFuture)
        await runner.setFailure(true)
        let failure = await model.loadPullRequest(for: branch, maxAge: 0)
        expect(failure != nil, "Explicit lookup bypasses fresh cache and returns failure")
        expect(model.branchPullRequest(for: branch)?.failure != nil, "Failure is kept with branch state")
        expect(model.pullRequest(for: branch) == old, "Failed refresh preserves the last known pull request")
        let uncached = BranchReference(directory: branch.directory, branch: "uncached")
        expect(await model.loadPullRequest(for: uncached, maxAge: 0) != nil, "First lookup failures are reported")
        expect(model.branchPullRequest(for: uncached)?.failure != nil, "First lookup failures are recorded")
        await runner.setFailure(false)
        let retry = await model.loadPullRequest(for: branch, maxAge: 0)
        expect(retry == nil, "Explicit retry checks again after sign-in failure")
        expect(model.branchPullRequest(for: branch)?.failure == nil, "Successful retry clears stale error")
        expect(model.currentLogin == "fixture", "Successful retry restores global GitHub availability")
        expect(model.accounts.error == nil, "Successful retry clears the account error consumed by the UI")
        await runner.blockNext()
        let older = Task { await model.loadPullRequest(for: branch, maxAge: 0) }
        while await runner.blocked == nil { await Task.yield() }
        let before = await runner.requests
        var finished = false
        let fresh = Task {
            _ = await model.loadPullRequest(for: branch, maxAge: 0)
            finished = true
        }
        await Task.yield()
        expect(!finished, "Explicit refresh waits for in-flight work")
        await runner.release()
        _ = await older.value
        await fresh.value
        expect(await runner.requests > before, "Explicit refresh reads again after older lookup")

        let missingRunner = SidebarRefreshRunner()
        await missingRunner.setInstalled(false)
        var rereadEnvironment = false
        let missing = GitHubModel(
            environment: { refresh in
                rereadEnvironment = rereadEnvironment || refresh; return [:]
            },
            runner: missingRunner, defaults: PreviewUserDefaults())
        await missing.refresh()
        expect(missing.availability == .notInstalled, "Missing gh is reported globally")
        await missingRunner.setInstalled(true)
        expect(await missing.loadPullRequest(for: branch, maxAge: 0) == nil, "Retry finds a newly installed gh")
        expect(rereadEnvironment, "Installation recovery rereads the environment")
        expect(missing.currentLogin == "fixture", "Installation recovery restores global availability")
        expect(missing.accounts.error == nil, "Installation recovery clears the account error")
    }
}
