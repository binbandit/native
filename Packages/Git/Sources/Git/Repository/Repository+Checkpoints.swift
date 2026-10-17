import Foundation

extension Repository {
    /// Saves the uncommitted state, untracked files included, under
    /// `refs/native-checkpoints/<name>-<timestamp>`, without touching the index or the working
    /// tree. Like a stash, the checkpoint commit sits on HEAD and has the index as its second
    /// parent, so `restore(_:paths:)` can bring back what was staged as well as what was on disk.
    /// Returns `nil` when there's nothing that isn't already safe in a branch.
    public func checkpoint(named name: String) async throws(GitError) -> Checkpoint? {
        let status = try await run(["status", "--porcelain=v2", "--branch", "-z", "--untracked-files=all"], readOnly: true)
        let (branch, changes) = try StatusParser.parse(status.text)
        // A detached HEAD's commits may be on no branch, so it's saved even when clean.
        guard !changes.isEmpty || (branch.isDetached && branch.commit != nil) else { return nil }

        // A scratch copy of the index, so neither tree touches the real one; starting from a copy
        // also means `add` only rehashes what changed.
        let scratch = FileManager.default.temporaryDirectory.appending(path: "native-checkpoint-\(UUID().uuidString).index")
        defer { try? FileManager.default.removeItem(at: scratch) }
        let indexPath = try await run(["rev-parse", "--path-format=absolute", "--git-path", "index"], readOnly: true)
            .text.trimmingCharacters(in: .whitespacesAndNewlines)
        try? FileManager.default.copyItem(at: URL(filePath: indexPath), to: scratch)
        let scratchEnvironment = ["GIT_INDEX_FILE": scratch.path(percentEncoded: false)]
        // An index with conflicts has no tree; the working tree alone is still worth saving.
        let indexTree = try await run(["write-tree"], environment: scratchEnvironment, acceptingStatus: [0, 128])
        try await run(["add", "--all"], environment: scratchEnvironment)
        let workingTree = try await run(["write-tree"], environment: scratchEnvironment).text.trimmingCharacters(in: .whitespacesAndNewlines)

        var parents = branch.commit.map { [$0] } ?? []
        if let head = branch.commit, indexTree.status == 0 {
            let tree = indexTree.text.trimmingCharacters(in: .whitespacesAndNewlines)
            parents.append(try await commitTree(tree, parents: [head], message: "Native checkpoint index"))
        }
        let commit = try await commitTree(workingTree, parents: parents, message: "Native checkpoint of \(root.path(percentEncoded: false))")

        let timestamp = Date.now.formatted(.iso8601.year().month().day().time(includingFractionalSeconds: true).dateTimeSeparator(.standard))
            .replacingOccurrences(of: ":", with: "")
            .replacingOccurrences(of: ".", with: "-")
        let reference = "refs/native-checkpoints/\(Worktree.slug(name, maxLength: 60))-\(timestamp)"
        try await run(["update-ref", reference, commit])
        return Checkpoint(reference: reference, commit: commit)
    }

    /// Checkpoints saved in this repository, newest first.
    public func checkpoints() async throws(GitError) -> [Checkpoint] {
        let output = try await run(["for-each-ref", "--sort=-creatordate", "--format=%(refname)%00%(objectname)", "refs/native-checkpoints"], readOnly: true)
        return output.text.split(separator: "\n").compactMap { line in
            let fields = line.split(separator: "\0")
            return fields.count == 2 ? Checkpoint(reference: String(fields[0]), commit: String(fields[1])) : nil
        }
    }

    /// Puts files back the way a checkpoint saved them, staged state included where the
    /// checkpoint has it. `nil` paths restores everything. Paths the checkpoint doesn't have are
    /// removed, so a discarded deletion is deleted again.
    public func restore(_ checkpoint: Checkpoint, paths: [String]? = nil) async throws(GitError) {
        let indexCommit = try await run(["rev-parse", "--verify", "--quiet", "\(checkpoint.commit)^2"], readOnly: true, acceptingStatus: [0, 1])
        if indexCommit.status == 0 {
            let source = indexCommit.text.trimmingCharacters(in: .whitespacesAndNewlines)
            // git refuses pathspecs that match nothing, in the source or the index.
            let staged = try await known(paths, in: source)
            if !staged.isEmpty {
                try await runWithPaths(["restore", "--source=\(source)", "--staged"], staged)
            }
        }
        let files = try await known(paths, in: checkpoint.commit)
        if !files.isEmpty {
            try await runWithPaths(["restore", "--source=\(checkpoint.commit)", "--worktree"], files)
        }
    }

    /// The requested paths that exist in `commit` or the index; `["."]`, everything, for `nil`.
    private func known(_ paths: [String]?, in commit: String) async throws(GitError) -> [String] {
        guard let paths else { return ["."] }
        let inCommit = try await run(["ls-tree", "-r", "-z", "--name-only", "--full-tree", commit], readOnly: true)
        let inIndex = try await run(["ls-files", "-z", "--full-name"], readOnly: true)
        let names = Set((inCommit.text + "\0" + inIndex.text).split(separator: "\0").map(String.init))
        return paths.filter(names.contains)
    }

    /// A commit by Native's own identity, unsigned: checkpoints are bookkeeping, and shouldn't fail
    /// on a missing `user.name` or wait on a signing prompt.
    private func commitTree(_ tree: String, parents: [String], message: String) async throws(GitError) -> String {
        let identity = [
            "GIT_AUTHOR_NAME": "Native", "GIT_AUTHOR_EMAIL": "native@localhost",
            "GIT_COMMITTER_NAME": "Native", "GIT_COMMITTER_EMAIL": "native@localhost",
        ]
        let arguments = ["commit-tree", tree, "--no-gpg-sign", "-m", message] + parents.flatMap { ["-p", $0] }
        return try await run(arguments, environment: identity).text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
