import Foundation

/// What a cleanup did that Undo takes back, in the order Undo goes: branches first, so the tasks'
/// worktrees can check them out again. Worktree records whose folders were already gone aren't
/// here; there's nothing to bring back.
struct GitCleanupUndo {
    /// Deleted branches, kept under `refs/native-archived-branches/` with their config.
    var branches: [String] = []
    /// Archived tasks; unarchiving one brings its worktree back (from its checkpoint).
    var tasks: [SessionKey] = []
    /// Folders of worktrees no task in Native worked in, put away the same way.
    var worktrees: [URL] = []
    /// Leftover folders moved to the Trash: where each was, and where it is now.
    var folders: [(original: URL, trashed: URL)] = []

    var isEmpty: Bool {
        branches.isEmpty && tasks.isEmpty && worktrees.isEmpty && folders.isEmpty
    }
}
