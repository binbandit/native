import ACP
import Exec
import Foundation
import Git
import GitHub
import TaskList

@testable import Native

/// Fixed gh JSON and git status only. No subprocess, credentials, network or external opener.
private actor SidebarPullRequestRunner: CommandRunner {
    var lookups = 0
    var merged = false
    var fails = false

    func setMerged() { merged = true }
    func setFailure() { fails = true }

    func run(_ command: Command) async throws -> CommandResult {
        let folder = command.directory ?? "/fixture"
        let number = Int(URL(filePath: folder).lastPathComponent) ?? 0
        let output: String
        if command.executable == "git" {
            switch command.arguments.first {
            case "rev-parse": output = "\(folder)\n\(folder)/.git\n\(folder)/.git\n"
            case "status": output = "# branch.oid abc123\0# branch.head task/\(number)\0"
            case "remote": output = "origin\n"
            default: output = ""
            }
        } else if command.arguments.first == "auth" {
            output =
                #"{"hosts":{"github.com":[{"state":"success","active":true,"host":"github.com","login":"fixture"}]}}"#
        } else if command.arguments.first == "api" {
            output = #"{"login":"fixture"}"#
        } else {
            lookups += 1
            if fails {
                return CommandResult(exitCode: 1, standardOutput: Data(), standardError: Data("offline".utf8))
            }
            let state = merged || number == 103 ? "MERGED" : number == 104 ? "CLOSED" : "OPEN"
            let checks =
                number == 105
                ? #"[{"__typename":"CheckRun","name":"Tests","status":"COMPLETED","conclusion":"FAILURE"}]"# : "[]"
            output =
                number == 0
                ? "[]"
                : """
                [{"number":\(number),"title":"Task \(number)","url":"https://github.com/fixture/sidebar/pull/\(number)",
                "state":"\(state)","isDraft":\(number == 102 && !merged),"headRefName":"task/\(number)","baseRefName":"main",
                "createdAt":"2026-10-01T00:00:00Z","updatedAt":"2026-10-01T00:00:00Z","statusCheckRollup":\(checks)}]
                """
        }
        return CommandResult(exitCode: 0, standardOutput: Data(output.utf8), standardError: Data())
    }
}

private struct SidebarPullRequestNoMonitor: RepositoryMonitor {
    func changes(in repository: Repository) -> AsyncStream<RepositoryChange> { AsyncStream { $0.finish() } }
}

@main @MainActor
private struct SidebarPullRequestChecks {
    static func check(_ result: Bool, _ message: String) {
        if !result { print("FAIL: \(message)"); exit(1) }
    }

    static func main() async throws {
        do {
            try await SidebarArchivedPullRequestChecks.run()
        } catch {
            print("FAIL: \(error)")
            exit(1)
        }
        let folder = FileManager.default.temporaryDirectory.appending(path: "sidebar-pr-\(UUID())")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let app = AppModel.preview(.empty)
        let project = app.projects.add(folder)
        let runner = SidebarPullRequestRunner()
        let git = GitStore(environment: { [:] }, turnBaselines: GitTurnBaselines(defaults: PreviewUserDefaults())) {
            _ in
            Git(environment: [:], runner: runner, monitor: SidebarPullRequestNoMonitor())
        }
        let github = GitHubModel(environment: { _ in [:] }, runner: runner, defaults: PreviewUserDefaults())
        var opened: [URL] = []
        github.openExternally = { opened.append($0) }
        let insights = AppSidebarTaskInsights.make(model: app, git: git, gitHub: github)
        let tasks = AppTaskPullRequests(model: app, git: git, gitHub: github)
        for number in [101, 102, 103, 104, 105, 0] {
            let checkout = folder.appending(path: "\(number)")
            try FileManager.default.createDirectory(at: checkout, withIntermediateDirectories: true)
            app.catalog.add(
                SessionInfo(sessionId: SessionID("pr-\(number)"), cwd: checkout.path, title: "Task \(number)"),
                for: AgentDefinition.ID(rawValue: "claude-code"), in: project.id)
        }
        // A task sharing the project checkout must not claim the project's branch.
        app.catalog.add(
            SessionInfo(sessionId: SessionID("shared"), cwd: folder.path),
            for: AgentDefinition.ID(rawValue: "claude-code"), in: project.id)
        for fact in TaskSidebarPreferences.Fact.allCases { app.sidebarPreferences.set(fact, shown: false) }
        let summaries = app.allSessions(in: project.id)
        await insights.prepare(summaries)
        for summary in summaries {
            let number = Int(URL(filePath: summary.info.cwd).lastPathComponent) ?? 0
            if number == 0 {
                check(insights.pullRequestBadge(summary) == nil, "No badge without a task PR")
                continue
            }
            check(insights.pullRequestBadge(summary) != nil, "Badge exists with all facts off: \(number)")
            check(tasks.pullRequest(of: summary)?.number == number, "Each task gets its own PR")
            let expected = [101: "open", 102: "draft", 103: "merged", 104: "closed", 105: "open"]
            let spoken = insights.pullRequestMenu(summary)?.spokenSummary ?? ""
            check(spoken.contains(expected[number] ?? "missing"), "Correct PR lifecycle: \(number)")
            if number == 105 { check(spoken.contains("failing"), "Failing checks reach the row") }
            let menu = insights.pullRequestMenu(summary)
            menu?.items.first { $0.title == "Open on GitHub" }?.perform()
            check(opened.last == tasks.pullRequest(of: summary)?.url, "Row menu opens its PR via the fake opener")
        }
        if let summary = summaries.first(where: { $0.id.id == SessionID("pr-105") }),
            let branch = tasks.branch(of: summary), var pr = tasks.pullRequest(of: summary)
        {
            pr.isDraft = true
            github.branchPullRequests[branch] = BranchPullRequest(pullRequest: pr, fetchedAt: .now)
            let spoken = insights.pullRequestMenu(summary)?.spokenSummary ?? ""
            check(spoken.contains("draft") && spoken.contains("failing"), "Draft failing checks stay accessible")
        }
        let count = await runner.lookups
        await insights.prepare(summaries)
        check(await runner.lookups == count, "Rows share the branch cache")
        ProjectRefreshWiring.connect(model: app, git: git, gitHub: github)
        await runner.setMerged()
        await app.refreshProject(project.id)
        for summary in summaries where tasks.checkout(of: summary) != nil {
            if let pr = tasks.pullRequest(of: summary) {
                check(pr.state == .merged, "Project Refresh updates outcomes")
            }
        }
        await runner.setFailure()
        await app.refreshProject(project.id)
        let withPR = summaries.filter { tasks.pullRequest(of: $0) != nil }
        if let archived = withPR.first {
            app.archivedSessions.set(archived.id, archived: true)
            check(insights.pullRequestBadge(archived) != nil, "Archived tasks keep their PR outcome")
            check(insights.pullRequestMenu(archived) != nil, "Archived tasks keep PR actions")
        }
        check(withPR.count == 5, "Failed refresh preserves all last-known outcomes")
        check(!app.problems.list(for: project.id).isEmpty, "Failed project refresh offers recovery")
        let fixture = SidebarPullRequestPreviewFixtures.model()
        let fixtureGit = SidebarPullRequestPreviewFixtures.git()
        let fixtureHub = SidebarPullRequestPreviewFixtures.gitHub()
        let fixtureInsights = AppSidebarTaskInsights.make(model: fixture, git: fixtureGit, gitHub: fixtureHub)
        let fixtureSummaries = fixture.projects.all.flatMap { fixture.allSessions(in: $0.id) }
        await fixtureInsights.prepare(fixtureSummaries)
        for summary in fixtureSummaries {
            check(fixtureInsights.pullRequestBadge(summary) != nil, "UI fixture has its real lookup data")
        }
        print("PASS: every PR state with facts off, no PR/shared checkout, cache, row menu and project refresh")
    }
}
