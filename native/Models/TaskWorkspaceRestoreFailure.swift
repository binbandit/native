import Foundation

/// Why the workspace of a task archived before Native kept a record of archived workspaces can't be
/// rebuilt from what's left (`TaskWorkspaceProvider.restoreWorkspace`), in plain words.
enum TaskWorkspaceRestoreFailure: LocalizedError, Hashable {
    /// No branch the task could have been on is left. `checkpoint` names its saved uncommitted work.
    case branchNotFound(checkpoint: String?)
    /// More than one branch could be the task's, so Native won't guess.
    case branchAmbiguous([String], checkpoint: String?)

    var errorDescription: String? {
        let archivedEarly = "It was archived before Native kept a record of archived worktrees, and "
        return switch self {
        case .branchNotFound:
            archivedEarly + "the branch it was on is gone: no branch, or copy Native keeps of a deleted one,"
                + " matches it."
        case .branchAmbiguous(let names, _):
            archivedEarly + "more than one branch could be the one it was on (\(names.joined(separator: ", ")))"
                + ", so Native won't guess."
        }
    }

    /// Where its uncommitted work is, when it had any.
    var savedWork: String? {
        switch self {
        case .branchNotFound(let checkpoint), .branchAmbiguous(_, let checkpoint):
            checkpoint.map { "Its uncommitted work is still saved, as \($0)." }
        }
    }
}
