import Foundation

/// One changed file in one area of the repository. A partly staged file appears twice: once
/// staged and once unstaged.
public struct FileChange: Hashable, Sendable, Identifiable {
    public enum Kind: Hashable, Sendable {
        case added, modified, deleted, renamed, copied, typeChanged, untracked, conflicted
    }

    /// Where the change lives, in the order lists show the areas.
    public enum Area: Int, Hashable, Sendable, CaseIterable, Comparable {
        /// Both sides changed the file in a merge, rebase or cherry-pick.
        case conflicted
        /// In the index, ready to commit.
        case staged
        /// In the working tree only.
        case unstaged
        /// A new file git doesn't track yet.
        case untracked

        public static func < (lhs: Area, rhs: Area) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }

    /// Relative to the repository root, with `/` separators.
    public var path: String
    /// The path before a rename or copy.
    public var originalPath: String?
    public var kind: Kind
    public var area: Area
    /// The entry is a submodule rather than a file.
    public var isSubmodule: Bool
    /// `nil` when unknown, e.g. for very large untracked files.
    public var stats: LineStats?

    public init(
        path: String, originalPath: String? = nil, kind: Kind, area: Area, isSubmodule: Bool = false,
        stats: LineStats? = nil
    ) {
        self.path = path
        self.originalPath = originalPath
        self.kind = kind
        self.area = area
        self.isSubmodule = isSubmodule
        self.stats = stats
    }

    public var id: String { "\(area):\(path)" }

    /// Every path the change touches: the path, and the original path of a rename.
    public var paths: [String] {
        [originalPath, path].compactMap(\.self)
    }

    /// The file's name without its directory.
    public var fileName: String {
        path.split(separator: "/").last.map(String.init) ?? path
    }

    /// The directory part of the path including its trailing `/`, or "" at the root.
    public var directory: String {
        guard let slash = path.lastIndex(of: "/") else { return "" }
        return String(path[...slash])
    }
}
