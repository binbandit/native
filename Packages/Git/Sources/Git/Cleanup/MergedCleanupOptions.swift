import Foundation

/// What `Repository.mergedCleanupPlan` needs to know that the repository can't tell it.
public struct MergedCleanupOptions: Sendable, Hashable {
    /// Where Native keeps this repository's task worktrees (`~/.native/worktrees/<repository>/`).
    /// Only worktrees and leftover folders inside it are ever offered for removal.
    public var taskLocation: URL
    /// The prefix Native names task branches with, such as "brayden/"; empty for none.
    public var branchPrefix: String
    /// The branch work has to be in; `nil` finds the default branch (the remote's HEAD, else
    /// main or master).
    public var base: String?
    /// Branch names never offered for deletion, besides the base and the main checkout's branch.
    /// A trailing `*` matches any rest: `release/*`.
    public var protectedBranches: [String]

    public static let defaultProtectedBranches = ["main", "master", "develop", "release/*"]

    public init(
        taskLocation: URL, branchPrefix: String = "", base: String? = nil,
        protectedBranches: [String] = MergedCleanupOptions.defaultProtectedBranches
    ) {
        self.taskLocation = taskLocation
        self.branchPrefix = branchPrefix
        self.base = base
        self.protectedBranches = protectedBranches
    }

    func isProtected(_ branch: String) -> Bool {
        protectedBranches.contains { pattern in
            pattern.hasSuffix("*") ? branch.hasPrefix(pattern.dropLast()) : branch == pattern
        }
    }
}
