import ACP
import Foundation

// Background work that failed for a project (`ProjectProblem`): what clients show with the project,
// and Retry and Dismiss, which every client drives through here.
extension AppModel {
    func isRetrying(_ problem: ProjectProblem) -> Bool {
        problems.retrying.contains(problem.id)
    }

    /// Does the failed work again. Working clears the problem; failing again keeps it, with the new
    /// error.
    func retry(_ problem: ProjectProblem) async {
        guard problems.beginRetry(problem.id) else { return }
        defer { problems.endRetry(problem.id) }
        guard let project = projects.project(problem.project) else {
            problems.resolve(problem.id)
            return
        }
        do {
            switch problem.work {
            case .refresh:
                await refreshProject(project.id)
                return
            case .folder:
                // Looking again, then listing what's there; both report how they went.
                checkFolder(of: project)
                await refreshSessions(in: project)
                return
            case .listing(let agent):
                // Listing reports how it went itself, as it does when Native lists on its own.
                await retryListing(in: project, of: agent)
                return
            case .agentCopyDeletion(let key):
                guard let route = taskActionRoute(for: key) else { throw TaskActionRoute.Failure.missingRoute }
                try await deleteAgentCopy(using: route, startingIfNeeded: true)
            case .workspaceDeletion(let key, let folder):
                if let route = taskActionRoute(for: key) {
                    try await deleteWorkspace(using: route)
                } else if !offersRemoteHosts, taskActionOwner(for: key) == .local {
                    // Legacy discarded local drafts have no catalog entry. Preserve their retry
                    // while remote hosts are off; enabled remote actions require a captured route.
                    try await taskWorkspaces?.deleteWorkspace(at: folder, in: project)
                } else {
                    throw TaskActionRoute.Failure.missingRoute
                }
            case .workspaceArchive(let key):
                _ = try await archiveWorkspace(of: key, in: project)
            case .workspaceRestore(let key):
                try await restoreWorkspace(of: key)
            }
            problems.resolve(problem.id)
        } catch {
            var again = problem
            again.details = error.localizedDescription.withoutTerminalEscapes
            problems.report(again)
        }
    }

    /// Takes the other way forward a problem offers (`ProjectProblem.alternative`), which settles it.
    func takeAlternative(of problem: ProjectProblem) async {
        guard let alternative = problem.alternative, projects.project(problem.project) != nil else { return }
        switch alternative {
        case .startInProjectFolder(let key):
            do {
                guard let route = taskActionRoute(for: key) else { throw TaskActionRoute.Failure.missingRoute }
                try await startInProjectFolder(using: route)
                problems.resolve(problem.id)
            } catch {
                var again = problem
                again.details = error.localizedDescription.withoutTerminalEscapes
                problems.report(again)
            }
        }
    }

    /// Lets a problem go without fixing it.
    func dismiss(_ problem: ProjectProblem) {
        problems.resolve(problem.id)
    }

}
