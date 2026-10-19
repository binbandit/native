import Foundation

/// The checkout a new task runs in, made by `GitStore.prepareTaskCheckout`.
struct GitTaskCheckout: Hashable, Sendable {
    let folder: URL
    /// Named provisionally; renamed after the task's title later.
    let branch: String
    /// Ignored files copied in from the project (worktrees only).
    let copiedFiles: [String]
}
