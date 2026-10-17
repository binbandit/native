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
            let url = root.appending(path: path, directoryHint: .notDirectory)
            let fileManager = FileManager.default
            // git stores a symlink as its target path.
            if let destination = try? fileManager.destinationOfSymbolicLink(atPath: url.path(percentEncoded: false)) {
                return Data(destination.utf8)
            }
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: url.path(percentEncoded: false), isDirectory: &isDirectory),
                !isDirectory.boolValue
            else {
                return nil
            }
            do {
                return try Data(contentsOf: url)
            } catch {
                throw .launchFailed("Couldn't read \(path): \(error.localizedDescription)")
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
            let isUnborn =
                try await run(["rev-parse", "--verify", "--quiet", "HEAD"], readOnly: true, acceptingStatus: [0, 1])
                .status != 0
            let base = isUnborn ? try await emptyTree() : "HEAD"
            let output = try await run(
                [
                    "--literal-pathspecs", "diff", base, "-M", "-U\(contextLines)", "--no-color", "--no-ext-diff",
                    "--no-textconv", "--",
                ] + tracked,
                readOnly: true
            )
            patch = output.text
        }
        for path in untracked.sorted() {
            guard let data = try await contents(of: path, at: .workingTree) else { continue }
            patch += "diff --git a/\(path) b/\(path)\nnew file\n--- /dev/null\n+++ b/\(path)\n"
            if FileVersions.isBinary(data) {
                patch += "Binary file\n"
            } else {
                for line in String(decoding: data, as: UTF8.self).split(
                    separator: "\n", omittingEmptySubsequences: false)
                {
                    patch += "+\(line)\n"
                }
            }
        }
        return patch
    }
}
