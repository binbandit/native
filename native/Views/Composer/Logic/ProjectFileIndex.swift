import Foundation

/// The files an `@` mention can pick from, for a task's project or worktree. Local projects list
/// them with git; an iPad will get them from its host through the same protocol.
protocol ProjectFileIndex: Sendable {
    /// Every file worth mentioning, relative to the project root, without ignored ones.
    func files() async throws -> [String]
    /// Files with uncommitted changes, which rank first.
    func changedFiles() async -> Set<String>
}
