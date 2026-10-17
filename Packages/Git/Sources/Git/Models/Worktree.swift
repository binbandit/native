import Foundation

/// A working tree of a repository: the main one or a linked worktree.
public struct Worktree: Hashable, Sendable, Identifiable {
    public var path: URL
    /// The checked-out commit; `nil` for a bare repository or before the first commit.
    public var head: String?
    /// The checked-out branch's short name; `nil` when detached or bare.
    public var branch: String?
    public var isMain: Bool
    public var isBare: Bool
    public var isDetached: Bool
    public var isLocked: Bool
    /// git would prune it, usually because its folder is gone.
    public var isPrunable: Bool

    public var id: URL { path }

    /// Where Native keeps task worktrees: `~/.native/worktrees/<repository>/<task>`, outside the
    /// repository so the main checkout's status, file watchers and searches never see them
    /// (the reference app moved its worktrees out of repositories for the same reason).
    public static var defaultLocation: URL {
        FileManager.default.homeDirectoryForCurrentUser.appending(
            path: ".native/worktrees", directoryHint: .isDirectory)
    }

    /// A folder and branch name for `title`: lowercase ASCII letters, digits and dashes.
    public static func slug(_ title: String, maxLength: Int = 40) -> String {
        let folded = title.folding(
            options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive],
            locale: Locale(identifier: "en_US_POSIX"))
        var slug = ""
        for scalar in folded.unicodeScalars {
            if ("a"..."z").contains(scalar) || ("0"..."9").contains(scalar) {
                slug.unicodeScalars.append(scalar)
            } else if !slug.isEmpty, !slug.hasSuffix("-") {
                slug.append("-")
            }
        }
        slug = String(slug.prefix(maxLength))
        while slug.hasSuffix("-") { slug.removeLast() }
        return slug.isEmpty ? "task" : slug
    }
}
