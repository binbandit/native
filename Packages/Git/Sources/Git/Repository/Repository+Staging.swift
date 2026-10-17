import Foundation

extension Repository {
    /// Stages the paths' working tree state, deletions included.
    public func stage(_ paths: [String]) async throws(GitError) {
        guard !paths.isEmpty else { return }
        try await runWithPaths(["add", "--all"], paths)
    }

    /// Takes the paths out of the index, leaving the working tree alone.
    public func unstage(_ paths: [String]) async throws(GitError) {
        guard !paths.isEmpty else { return }
        // `reset` also works before the first commit, where `restore --staged` doesn't.
        try await runWithPaths(["reset", "--quiet"], paths)
    }

    /// The paths that `.gitignore` and friends exclude. Tracked files never count as ignored.
    public func ignoredPaths(among paths: [String]) async throws(GitError) -> Set<String> {
        guard !paths.isEmpty else { return [] }
        var input = Data()
        for path in paths {
            input.append(contentsOf: path.utf8)
            input.append(0)
        }
        // 1: none of them are ignored.
        let output = try await run(
            ["check-ignore", "-z", "--stdin"], readOnly: true, input: input, acceptingStatus: [0, 1])
        return Set(output.text.split(separator: "\0").map(String.init))
    }
}
