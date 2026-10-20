import Foundation

/// One file that differs between two trees or commits, as `git diff-tree` reports it: what a
/// stretch of work changed, committed or not, when both ends are snapshots or commits.
public struct TreeChange: Hashable, Sendable, Identifiable {
    /// Relative to the repository root, with `/` separators; the new path of a rename.
    public var path: String
    /// The path before a rename or copy.
    public var originalPath: String?
    /// Added, modified, deleted, renamed, copied or type changed.
    public var kind: FileChange.Kind
    /// The entry is a submodule rather than a file.
    public var isSubmodule: Bool
    /// `nil` when git didn't count the lines.
    public var stats: LineStats?

    public init(
        path: String, originalPath: String? = nil, kind: FileChange.Kind, isSubmodule: Bool = false,
        stats: LineStats? = nil
    ) {
        self.path = path
        self.originalPath = originalPath
        self.kind = kind
        self.isSubmodule = isSubmodule
        self.stats = stats
    }

    public var id: String { path }

    /// Every path the change touches: the path, and the original path of a rename or copy.
    public var paths: [String] {
        [originalPath, path].compactMap(\.self)
    }
}
