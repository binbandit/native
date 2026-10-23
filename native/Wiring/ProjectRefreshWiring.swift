import Foundation

/// Connects the model action to existing git and GitHub services. A shared checkout is read once,
/// including tasks hidden by pins, filters, folding or the archive.
@MainActor
enum ProjectRefreshWiring {
    static func connect(model: AppModel, git: GitStore, gitHub: GitHubModel) {
        model.refreshProjectState = { [weak model] _, summaries in
            guard let model else { return [] }
            var visited: Set<ObjectIdentifier> = []
            var failures: [String] = []
            for summary in summaries {
                let folder = URL(filePath: summary.info.cwd, directoryHint: .isDirectory)
                let repository = git.model(for: folder, session: summary.id)
                let isMissing = repository.isLocal && !FileManager.default.fileExists(atPath: folder.path)
                // Archive intentionally removes managed worktrees. Never recreate one to refresh it.
                if isMissing, model.isArchived(summary.id) { continue }
                guard visited.insert(ObjectIdentifier(repository)).inserted else { continue }
                if isMissing {
                    failures.append("\(model.title(for: summary)): its folder is missing. Restore it, then Retry.")
                    continue
                }
                await repository.refreshNow()
                if let failure = repository.refreshFailure {
                    failures.append("\(model.title(for: summary)): \(failure.withoutTerminalEscapes)")
                    continue
                }
                guard repository.hasRemote, let branch = repository.branch?.name else { continue }
                guard repository.isLocal else {
                    failures.append(
                        "Pull-request state on a paired host isn't available here yet. Check it on that host.")
                    continue
                }
                if let failure = await gitHub.loadPullRequest(
                    for: BranchReference(directory: folder, branch: branch), maxAge: 0)
                {
                    failures.append(
                        [failure.localizedDescription, failure.recoverySuggestion]
                            .compactMap { $0 }.joined(separator: " ").withoutTerminalEscapes)
                }
            }
            return failures
        }
    }
}
