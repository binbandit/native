import Exec
import Foundation
import GitHub

@testable import Native

/// Only the injected runner answers these requests; no GitHub credentials or network are used.
private actor SidebarRefreshRunner: CommandRunner {
    var requests = 0
    var fails = false
    var blocked: CheckedContinuation<Void, Never>?
    var shouldBlock = false

    func setFailure(_ value: Bool) { fails = value }
    func blockNext() { shouldBlock = true }
    func release() { blocked?.resume(); blocked = nil }

    func run(_ command: Command) async throws -> CommandResult {
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

@main
@MainActor
private struct SidebarTrioRegression {
    static var failures = 0

    static func expect(_ result: Bool, _ message: String) {
        if !result { print("FAIL: \(message)"); failures += 1 }
    }

    static func main() async {
        await modelActions()
        await branchRefreshes()
        let unavailable = GitRepositoryModel(unavailableFolder: URL(filePath: "/fixture/remote"))
        await unavailable.refreshNow()
        expect(unavailable.refreshFailure?.contains("Reconnect") == true, "Unavailable hosts explain recovery")
        if failures > 0 { exit(1) }
        print("PASS: archive groups, full project scope, refresh gating, Retry, cache bypass and in-flight lookup")
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
        model.branchPullRequests[branch] = BranchPullRequest(pullRequest: old, fetchedAt: .now)
        await runner.setFailure(true)
        let failure = await model.loadPullRequest(for: branch, maxAge: 0)
        expect(failure != nil, "Explicit lookup bypasses fresh cache and returns failure")
        expect(model.branchPullRequest(for: branch)?.failure != nil, "Failure is kept with branch state")
        expect(model.pullRequest(for: branch) == old, "Failed refresh preserves the last known pull request")
        await runner.setFailure(false)
        let retry = await model.loadPullRequest(for: branch, maxAge: 0)
        expect(retry == nil, "Explicit retry checks again after sign-in failure")
        expect(model.branchPullRequest(for: branch)?.failure == nil, "Successful retry clears stale error")
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
    }
}
