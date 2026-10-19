import Foundation

extension Repository {
    /// Copies files git ignores that match `patterns` (env files, local config) from this working
    /// tree into the same paths under `destination`, a new worktree of the same repository. Files
    /// already there are kept. Returns the paths copied.
    @discardableResult
    public func copyIgnoredFiles(matching patterns: [String], to destination: URL) async throws(GitError) -> [String] {
        guard !patterns.isEmpty else { return [] }
        let matcher = FilePatterns(patterns: patterns)
        // `--directory` folds wholly ignored folders (node_modules) into one entry instead of
        // listing every file in them.
        let ignored = ["ls-files", "-z", "--others", "--ignored", "--exclude-standard"]
        let listing = try await run(ignored + ["--directory"], readOnly: true)
        var files: [String] = []
        var folders: [String] = []
        for entry in listing.text.split(separator: "\0").map(String.init) {
            if entry.hasSuffix("/") {
                if matcher.matches(String(entry.dropLast())) { folders.append(entry) }
            } else if matcher.matches(entry) {
                files.append(entry)
            }
        }
        if !folders.isEmpty {
            files += try await run(ignored + ["--"] + folders, readOnly: true).text.split(separator: "\0").map(
                String.init)
        }
        guard !files.isEmpty else { return [] }
        // One shell for all of them, on the machine the repository is on.
        let script =
            #"dest=$1; shift; for f; do [ -e "$dest/$f" ] && continue; mkdir -p "$dest/$(dirname -- "$f")" && cp -p -- "$f" "$dest/$f" || exit 1; done"#
        let output = try await git.runTool(
            "sh", ["-c", script, "sh", destination.path(percentEncoded: false)] + files, in: root)
        guard output.status == 0 else {
            throw .failed(arguments: ["cp"], status: output.status, stderr: output.stderr)
        }
        return files
    }

    /// The branch checked out here, or nil when HEAD is detached. Cheaper than `status()`, for
    /// noting the branch a new worktree starts from.
    public func currentBranchName() async throws(GitError) -> String? {
        let output = try await run(
            ["symbolic-ref", "--quiet", "--short", "HEAD"], readOnly: true, acceptingStatus: [0, 1])
        let name = output.text.trimmingCharacters(in: .whitespacesAndNewlines)
        return output.status == 0 && !name.isEmpty ? name : nil
    }
}
