#if DEBUG
import ACP
import Git
import GitHub
import SwiftUI
import TaskList

enum SidebarPullRequestPreviewFixtures {
    static let pullRequests: [PullRequestSummary] = [
        make(101, "Retry uploads", state: .open),
        make(102, "Draft the migration", state: .open, draft: true),
        make(103, "Wrap diff lines", state: .merged),
        make(104, "Explore another layout", state: .closed),
        make(105, "Fix failing tests", state: .open, failing: true),
        make(106, "Archive the migration", state: .merged),
    ]

    private static func make(
        _ number: Int, _ title: String, state: PullRequest.State, draft: Bool = false, failing: Bool = false
    ) -> PullRequestSummary {
        PullRequestPreviewFixtures.summary(
            "fixture/sidebar", number, title, branch: "task/\(number)", minutesAgo: 1,
            isDraft: draft, state: state, author: "fixture",
            checks: failing ? CheckSummary(state: .failing, passed: 4, failed: 1) : nil)
    }

    static var checkouts: [URL] {
        let root = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        return ["GitHub", "Git", "TaskPeek", "Views", "DesignSystem", "Plugins"].map { root.appending(path: $0) }
    }

    static func defaults() -> UserDefaults {
        let defaults = PreviewUserDefaults()
        defaults.set(true, forKey: "sidebar.showsArchived")
        return defaults
    }

    static func git() -> GitStore {
        GitStore(environment: { [:] }, turnBaselines: GitTurnBaselines(defaults: PreviewUserDefaults())) { _ in
            Git(
                environment: [:], runner: SidebarPullRequestFixtureRunner(), monitor: SidebarPullRequestFixtureMonitor()
            )
        }
    }

    static func gitHub() -> GitHubModel {
        GitHubModel(
            environment: { _ in [:] }, runner: SidebarPullRequestFixtureRunner(), defaults: PreviewUserDefaults())
    }

    static func model() -> AppModel {
        let app = AppModel.preview(.empty)
        let project = app.projects.add(URL(filePath: "/fixture/sidebar"))
        for (index, pullRequest) in pullRequests.enumerated() {
            let id = "pr-\(pullRequest.number)"
            app.catalog.add(
                SessionInfo(sessionId: SessionID(id), cwd: checkouts[index].path, title: pullRequest.title),
                for: AgentDefinition.ID(rawValue: "claude-code"), in: project.id)
            if let session = SessionModel.preview(
                in: app, agent: "claude-code", id: id, cwd: checkouts[index].path, title: pullRequest.title)
            {
                session.previewExchange(pullRequest.title, reply: "The change is ready to review.")
            }
        }
        for fact in TaskSidebarPreferences.Fact.allCases { app.sidebarPreferences.set(fact, shown: false) }
        app.archivedSessions.set(
            SessionKey(agent: AgentDefinition.ID(rawValue: "claude-code"), id: SessionID("pr-106")), archived: true)
        app.selection = app.sessionList.first { $0.id.id == SessionID("pr-105") }?.id
        return app
    }

}
#endif
