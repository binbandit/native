import Foundation
import Git
import GitHub

/// Connects expeditions to the features they're composed from: sessions (AppModel), the crew's
/// worktree (Git), the pull request at the end (GitHub, the same way workflows open theirs), and
/// provider limits (Usage).
enum ExpeditionWiring {
    static func connect(_ center: ExpeditionCenter, model: AppModel, git: GitStore, gitHub: GitHubModel) {
        center.connect(
            to: model,
            prepareBase: { [git] project, title, _ in
                try await git.createTaskWorktree(in: project, title: "expedition \(title)")
            },
            openPullRequest: { [git, gitHub] draft in
                try await AutomationGitHubWiring.openPullRequest(draft, git: git, gitHub: gitHub)
            },
            limitStatus: { BuiltInPlugins.usage.limits.limitStatus(for: $0) }
        )
        center.probe = { [git, gitHub] project in await probe(project, git: git, gitHub: gitHub) }
    }

    private static func probe(_ project: URL, git: GitStore, gitHub: GitHubModel) async -> ExpeditionProjectProbe {
        let model = git.model(for: project)
        if model.repository == nil {
            await model.refreshNow()
        }
        let ready: Bool? =
            switch gitHub.availability {
            case .ready: true
            case .notInstalled, .notAuthenticated: false
            case .offline, nil: nil
            }
        return ExpeditionProjectProbe(
            isRepository: model.repository != nil, hasUncommittedChanges: !model.changes.isEmpty, gitHubReady: ready)
    }
}
