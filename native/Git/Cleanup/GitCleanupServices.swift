import Foundation
import Git

/// What Clean Up Merged works with, from the app's wiring: the tasks (to archive them through the
/// normal archive path), git, and GitHub through closures so the Git feature doesn't know it.
struct GitCleanupServices {
    let app: AppModel
    let git: GitStore
    /// The prefix Native names a project's task branches with now.
    let branchPrefix: @MainActor (_ project: URL) async -> String
    /// Merged pull requests for the branches asked about, or why GitHub couldn't be asked.
    let pullRequests:
        @MainActor (_ queries: [CleanupPullRequestLookup.Query], _ project: URL) async -> CleanupPullRequestLookup
}
