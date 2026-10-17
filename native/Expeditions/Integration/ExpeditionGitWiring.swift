#if EXPEDITIONS_WIP
import Foundation
import Git
import GitHub

/// Connects expeditions to the Git and GitHub features: the crew's worktree, and what the
/// readiness checks need to know about a project.
enum ExpeditionGitWiring {
    /// A fresh worktree for the crew, on a branch named after the expedition.
    static func base(for project: URL, title: String, git: GitStore) async throws -> URL {
        try await git.createTaskWorktree(in: project, title: "expedition \(title)")
    }

    static func probe(_ project: URL, git: GitStore, gitHub: GitHubModel) async -> ExpeditionProjectProbe {
        let model = git.model(for: project)
        if model.repository == nil {
            await model.refreshNow()
        }
        let ready: Bool? = switch gitHub.availability {
        case .ready: true
        case .notInstalled, .notAuthenticated: false
        case .offline, nil: nil
        }
        return ExpeditionProjectProbe(isRepository: model.repository != nil, hasUncommittedChanges: !model.changes.isEmpty, gitHubReady: ready)
    }
}
#endif
