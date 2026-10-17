import Foundation

/// What changed in a repository, as one batch of file system events.
public struct RepositoryChange: Sendable, Hashable {
    /// Working tree files that changed, relative to the root. These may be ignored files; check
    /// with `Repository.ignoredPaths(among:)` before doing anything expensive.
    public var paths: Set<String> = []
    /// HEAD, the index or a branch moved: a commit, checkout, stage or push happened.
    public var gitStateChanged = false

    public var isEmpty: Bool { paths.isEmpty && !gitStateChanged }
}
