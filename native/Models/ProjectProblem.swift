import Foundation

/// Work Native did on its own for a project that failed: finding its folder, listing its sessions,
/// or tidying up after a task was archived, brought back or deleted. It stays with the project, for any client to show
/// where the project is, until the work succeeds, the user retries it or they dismiss it. Never an
/// alert: the user didn't just ask for this, so it waits quietly where they'll look.
struct ProjectProblem: Identifiable, Hashable {
    /// What failed, which is also what Retry does again.
    enum Work: Hashable {
        /// Finding the project's folder, which was moved or deleted. Retry looks again.
        case folder
        /// Listing the project's sessions from an agent.
        case listing(AgentDefinition.ID)
        /// Deleting the agent's own copy of a task Native deleted.
        case agentCopyDeletion(SessionKey)
        /// Removing the workspace Native made for a deleted task.
        case workspaceDeletion(SessionKey, folder: URL)
        /// Putting away the workspace of an archived task.
        case workspaceArchive(SessionKey)
        /// Bringing back the workspace of a task taken out of the archive.
        case workspaceRestore(SessionKey)
    }

    /// One per piece of work: a new failure of the same work replaces the old one.
    struct ID: Hashable {
        let project: Project.ID
        let work: Work
    }

    let project: Project.ID
    let work: Work
    /// What happened, in plain words and short enough for a sidebar row: "Couldn't list Codex sessions".
    let title: String
    /// What Native already did about it, or where things stand now.
    let recovery: String
    /// What the user can do, beyond retrying.
    var suggestion: String?
    /// The underlying error, for Show Details; a failed retry replaces it.
    var details: String?

    var id: ID {
        ID(project: project, work: work)
    }
}
