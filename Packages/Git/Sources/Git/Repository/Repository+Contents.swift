import Foundation

extension Repository {
    public enum Revision: Hashable, Sendable {
        case head
        case index
        case workingTree
    }

    /// A file's bytes at `revision`, or `nil` when it doesn't exist there.
    public func contents(of path: String, at revision: Revision) async throws(GitError) -> Data? {
        switch revision {
        case .head, .index:
            // `:0:` names stage 0 explicitly, so paths that look like `:1:x` can't be misread.
            let object = revision == .head ? "HEAD:\(path)" : ":0:\(path)"
            let output = try await run(["cat-file", "blob", object], readOnly: true, acceptingStatus: [0, 128])
            return output.status == 0 ? output.stdout : nil
        case .workingTree:
            // Read on the machine the repository is on. git stores a symlink as its target path,
            // so a link reads as that; a missing file or a folder exits 3.
            let script =
                #"if [ -L "$1" ]; then printf '%s' "$(readlink -- "$1")"; elif [ -f "$1" ]; then cat -- "$1"; else exit 3; fi"#
            let output = try await git.runTool("sh", ["-c", script, "sh", path], in: root)
            switch output.status {
            case 0: return output.stdout
            case 3: return nil
            default: throw .launchFailed("Couldn't read \(path): \(output.stderr)")
            }
        }
    }

    /// The two sides of a change, as a diff of it would compare them.
    public func versions(of change: FileChange) async throws(GitError) -> FileVersions {
        let old: Data?
        let new: Data?
        switch change.area {
        case .staged:
            old =
                change.kind == .added || change.kind == .copied
                ? nil : try await contents(of: change.originalPath ?? change.path, at: .head)
            new = change.kind == .deleted ? nil : try await contents(of: change.path, at: .index)
        case .unstaged:
            old = change.kind == .added ? nil : try await contents(of: change.path, at: .index)
            new = change.kind == .deleted ? nil : try await contents(of: change.path, at: .workingTree)
        case .untracked:
            old = nil
            new = try await contents(of: change.path, at: .workingTree)
        case .conflicted:
            old = try await contents(of: change.path, at: .head)
            new = try await contents(of: change.path, at: .workingTree)
        }
        return FileVersions(path: change.path, old: old, new: new)
    }

    /// A unified diff of the changes against HEAD, untracked files included as additions. Meant
    /// for summarizing, e.g. drafting a commit message; trimming is up to the caller.
    public func patch(for changes: [FileChange], contextLines: Int = 2) async throws(GitError) -> String {
        let untracked = Set(changes.filter { $0.area == .untracked }.map(\.path))
        let tracked = Array(Set(changes.filter { $0.area != .untracked }.flatMap(\.paths)).subtracting(untracked))
            .sorted()
        var patch = ""
        if !tracked.isEmpty {
            let base = try await resolve("HEAD") == nil ? try await emptyTree() : "HEAD"
            let output = try await run(
                [
                    "--literal-pathspecs", "diff", base, "-M", "-U\(contextLines)", "--no-color", "--no-ext-diff",
                    "--no-textconv", "--",
                ] + tracked,
                readOnly: true
            )
            patch = output.text
        }
        if !untracked.isEmpty {
            let output = try await diffUntracked(
                untracked.sorted(),
                ["-U\(contextLines)", "--no-color", "--no-ext-diff", "--no-textconv"]
            )
            patch += output.text
        }
        return patch
    }
}
