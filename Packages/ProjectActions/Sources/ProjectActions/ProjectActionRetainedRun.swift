import Foundation

/// Output belongs to the task's worktree, independently of the project's Run Last preference.
public struct ProjectActionRetainedRun: Sendable {
    public let action: ProjectAction
    public let worktree: URL
    public let startedAt: Date

    public init(action: ProjectAction, worktree: URL, startedAt: Date) {
        self.action = action
        self.worktree = worktree
        self.startedAt = startedAt
    }

    public static func latest(in worktree: URL, from runs: [Self]) -> Self? {
        let folder = worktree.standardizedFileURL.path(percentEncoded: false)
        return runs.filter { $0.worktree.standardizedFileURL.path(percentEncoded: false) == folder }
            .max { $0.startedAt < $1.startedAt }
    }
}
