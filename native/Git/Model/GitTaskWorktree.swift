import Foundation

/// A task worktree Native just made or is about to remove, for the scripts that run around it.
struct GitTaskWorktree: Hashable, Sendable {
    let folder: URL
    /// The project's main checkout.
    let projectRoot: URL
    let branch: String?
    /// The branch the worktree was made from, when Native made it from one.
    var baseBranch: String?
    /// Ignored files copied in from the project.
    var copiedFiles: [String] = []
    /// Why copying them failed, if it did.
    var copyFailure: String?
    /// A quiet explanation when the new task uses a local base.
    var baseNotice: String?
}
