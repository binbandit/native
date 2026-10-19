import Foundation

/// The git queries behind `mergedCleanupPlan`: the base branch, each local branch's state, and
/// what's on disk in Native's task worktree location. All read-only.
extension Repository {
    /// The base branch's name and the refs that count as it: the local branch and the remote's
    /// copy, since work merged on GitHub may only be in the remote's.
    struct CleanupBase {
        let name: String
        let refs: [String]
    }

    /// A local branch, as `for-each-ref` sees it.
    struct LocalBranchFacts {
        let name: String
        let tip: String
        /// The branch it pulls from on its remote ("refs/heads/fix"), when it tracks one.
        let upstreamRef: String?
    }

    func cleanupBase(preferred: String?) async throws(GitError) -> CleanupBase {
        let remotes = try await remotes()
        let remote = remotes.contains("origin") ? "origin" : remotes.first
        var name = preferred
        if name == nil, let remote {
            let head = try await run(
                ["symbolic-ref", "--quiet", "--short", "refs/remotes/\(remote)/HEAD"], readOnly: true,
                acceptingStatus: [0, 1, 128])
            let short = head.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if head.status == 0, short.hasPrefix(remote + "/") {
                name = String(short.dropFirst(remote.count + 1))
            }
        }
        if name == nil {
            for candidate in ["main", "master", "trunk"] where try await resolve("refs/heads/\(candidate)") != nil {
                name = candidate
                break
            }
        }
        guard let name else {
            throw .failed(
                arguments: ["symbolic-ref", "refs/remotes/origin/HEAD"], status: 1,
                stderr: "Couldn't tell which branch is the main one: there's no main or master branch.")
        }
        var refs: [String] = []
        if try await resolve("refs/heads/\(name)") != nil { refs.append(name) }
        if let remote, try await resolve("refs/remotes/\(remote)/\(name)") != nil { refs.append("\(remote)/\(name)") }
        guard !refs.isEmpty else {
            throw .failed(arguments: ["rev-parse", name], status: 128, stderr: "There's no branch named “\(name)”.")
        }
        return CleanupBase(name: name, refs: refs)
    }

    func localBranchFacts() async throws(GitError) -> [LocalBranchFacts] {
        let output = try await run(
            ["for-each-ref", "--format=%(refname:short)%00%(objectname)%00%(upstream:remoteref)", "refs/heads"],
            readOnly: true)
        return output.text.split(separator: "\n").compactMap { line in
            let fields = line.split(separator: "\0", omittingEmptySubsequences: false).map(String.init)
            guard fields.count == 3 else { return nil }
            return LocalBranchFacts(name: fields[0], tip: fields[1], upstreamRef: fields[2].isEmpty ? nil : fields[2])
        }
    }

    /// Branch names some remote has, without the remote: "fix" for `origin/fix`.
    func remoteBranchNames() async throws(GitError) -> Set<String> {
        let output = try await run(["for-each-ref", "--format=%(refname)", "refs/remotes"], readOnly: true)
        return Set(
            output.text.split(separator: "\n").compactMap { reference in
                reference.dropFirst("refs/remotes/".count).split(separator: "/", maxSplits: 1).last.map(String.init)
            })
    }

    /// The local branches whose tips are in a base ref's history (`git branch --merged`).
    func branchesMerged(into base: CleanupBase) async throws(GitError) -> Set<String> {
        var merged: Set<String> = []
        for reference in base.refs {
            let output = try await run(
                ["branch", "--merged", reference, "--format=%(refname:short)"], readOnly: true)
            merged.formUnion(output.text.split(separator: "\n").map(String.init))
        }
        return merged
    }

    /// Whether the branch ever moved after it was made, from its reflog. A branch made for a task
    /// that never committed sits where it started, which `git branch --merged` counts as merged.
    /// Without a reflog (expired, or turned off) it's assumed to have.
    func hasCommitsOfItsOwn(_ branch: String) async -> Bool {
        guard
            let output = try? await run(
                ["reflog", "show", "--format=%H", "refs/heads/\(branch)", "--"], readOnly: true,
                acceptingStatus: [0, 128]),
            output.status == 0
        else { return true }
        let tips = Set(output.text.split(separator: "\n"))
        return tips.count != 1
    }

    /// Whether merging `branch` into one of the base refs would change nothing, so its changes are
    /// already there (a squash or rebase merge). Needs git 2.38's `merge-tree --write-tree`; older
    /// git, or a conflict, says no.
    func changesAreIn(_ base: CleanupBase, branch: String) async -> Bool {
        for reference in base.refs.reversed() {
            guard
                let merge = try? await run(
                    ["merge-tree", "--write-tree", "--no-messages", reference, "refs/heads/\(branch)"], readOnly: true,
                    acceptingStatus: [0, 1, 128, 129]),
                merge.status == 0,
                let tree = merge.text.split(separator: "\n").first.map(String.init),
                let baseTree = try? await resolve("\(reference)^{tree}")
            else { continue }
            if tree == baseTree { return true }
        }
        return false
    }

    /// Commits in `revision`'s history that none of the base refs have.
    func commitsNotIn(_ base: CleanupBase, revision: String) async throws(GitError) -> Int {
        let output = try await run(["rev-list", "--count", revision, "--not"] + base.refs, readOnly: true)
        return Int(output.text.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
    }

    /// Whether a commit is in any of the base refs' history.
    func isIn(_ base: CleanupBase, commit: String) async throws(GitError) -> Bool {
        for reference in base.refs where try await contains(commit, in: reference) {
            return true
        }
        return false
    }

    /// Files with uncommitted changes in a worktree, untracked ones included.
    func uncommittedFileCount(in worktree: URL) async throws(GitError) -> Int {
        let output = try await git.run(
            ["status", "--porcelain=v2", "--branch", "-z", "--untracked-files=all"], in: worktree, readOnly: true)
        return Set(try StatusParser.parse(output.text).changes.map(\.path)).count
    }

    // MARK: - Folders

    /// `folder` with symlinks resolved, as git spells worktree paths; `nil` when it doesn't exist.
    func physicalPath(of folder: URL) async -> String? {
        guard
            let output = try? await git.runTool(
                "/bin/sh", ["-c", "cd \"$1\" && pwd -P", "sh", folder.path(percentEncoded: false)], in: nil),
            output.status == 0
        else { return nil }
        let path = output.text.trimmingCharacters(in: .newlines)
        return path.isEmpty ? nil : path
    }

    /// Bytes on disk under `folder`, from `du`.
    func diskUsage(of folder: URL) async -> Int? {
        guard let output = try? await git.runTool("du", ["-sk", folder.path(percentEncoded: false)], in: nil),
            output.status == 0,
            let kilobytes = output.text.split(whereSeparator: \.isWhitespace).first.flatMap({ Int($0) })
        else { return nil }
        return kilobytes * 1024
    }

    /// Folders in Native's task location (`location`, as git spells it) that a worktree of this
    /// repository left behind: their `.git` file points into this repository's worktree records,
    /// at one that's gone. Folders of other repositories, and anything else, are never included.
    func leftoverTaskFolders(in location: String, listed: Set<String>) async -> [URL] {
        guard
            let entries = try? await git.runTool(
                "find", [location, "-mindepth", "1", "-maxdepth", "1", "-type", "d"], in: nil),
            entries.status == 0,
            let common = await physicalPath(of: commonDirectory)
        else { return [] }
        var leftovers: [URL] = []
        for path in entries.text.split(separator: "\n").map(String.init).sorted() where !listed.contains(path) {
            guard let file = try? await git.runTool("cat", ["\(path)/.git"], in: nil), file.status == 0 else {
                continue
            }
            let gitdir = file.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard gitdir.hasPrefix("gitdir: ") else { continue }
            let record = String(gitdir.dropFirst("gitdir: ".count))
            guard record.hasPrefix(common + "/worktrees/"),
                let exists = try? await git.runTool("test", ["-e", record], in: nil), exists.status != 0
            else { continue }
            leftovers.append(URL(filePath: path, directoryHint: .isDirectory))
        }
        return leftovers
    }
}
