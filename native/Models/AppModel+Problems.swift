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
                try await deleteAgentCopy(of: key)
            case .workspaceDeletion(_, let folder):
                try await taskWorkspaces?.deleteWorkspace(at: folder, in: project)
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
        guard let alternative = problem.alternative, let project = projects.project(problem.project) else { return }
        switch alternative {
        case .startInProjectFolder(let key):
            do {
                _ = try await startTask(
                    in: project.id, folder: project.url, title: titleOfSession(key), agent: key.agent)
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

    /// Asks the agent to delete its copy of a deleted task, starting the agent if it's stopped.
    private func deleteAgentCopy(of key: SessionKey) async throws {
        guard let runtime = await ensureRunning(key.agent), let connection = runtime.connection else {
            throw ProjectProblemRetryFailure(errorDescription: startFailure(of: key.agent))
        }
        // An agent that can't delete sessions anymore has nothing left to do.
        guard runtime.capabilities?.deleteSessions == true else { return }
        _ = try await connection.send(DeleteSessionRequest(sessionId: key.id))
    }
}

/// Why a retry couldn't even begin, such as the agent not starting.
private struct ProjectProblemRetryFailure: LocalizedError {
    let errorDescription: String?
}
