import Foundation

/// Task worktrees archived by Native before it recorded what brings one back
/// (`recordArchivedWorktree`). Those archives left only the checkpoint of the folder's uncommitted
/// work and the branch (kept, or deleted with a copy under `refs/native-archived-branches/`), so
/// the record is worked out again from them.
extension Repository {
    /// Works out what brings back the task worktree that was at `path`, archived at `archivedAt` by
    /// a task titled `title`.
    ///
    /// The checkpoint is the one the archive made of that folder: named after it, its message
    /// naming the folder, and made no earlier than the archive. Without one the folder had nothing
    /// uncommitted. The branch is found by the first kind of evidence any branch has, and must
    /// hold the commit the checkpoint was made on:
    /// 1. Its name: the folder is named after the provisional branch's code (or after the branch,
    ///    for a pull request's worktree), which a branch renamed after its title keeps in its reflog.
    /// 2. The task's title, which renamed it.
    /// 3. Being the only branch at the commit the checkpoint was made on.
    /// More than one branch with the same evidence is ambiguous. `isSameFolder` compares the
    /// folder with the one a checkpoint names, as git spelled it (`/private/tmp/x` for `/tmp/x`).
    public func rebuildArchivedWorktree(
        at path: URL, title: String?, archivedAt: Date?,
        isSameFolder: (_ path: String, _ named: String) -> Bool = { $0 == $1 }
    ) async throws(GitError) -> RebuiltArchivedWorktree {
        let folderName = path.lastPathComponent
        let checkpoint = try await archiveCheckpoint(of: path, since: archivedAt, isSameFolder: isSameFolder)
        var base: String?
        if let checkpoint {
            base = try await resolve("\(checkpoint.commit)^1")
        }
        let candidates = try await legacyBranchCandidates()
        var consistent: [LegacyBranchCandidate] = []
        for candidate in candidates {
            if let base, candidate.tip != base, try await !contains(base, in: candidate.tip) { continue }
            consistent.append(candidate)
        }

        var byName: [LegacyBranchCandidate] = []
        for candidate in consistent {
            if Self.isNamed(candidate.name, after: folderName) {
                byName.append(candidate)
            } else if !candidate.isArchivedCopy,
                try await renamedFrom(candidate.name).contains(where: { Self.isNamed($0, after: folderName) })
            {
                byName.append(candidate)
            }
        }
        let titleSlug = title.map { Worktree.slug($0) }.flatMap { $0.isEmpty ? nil : $0 }
        let byTitle = consistent.filter { candidate in
            guard let titleSlug else { return false }
            // Made unique with a number when the name was taken: "fix-login-2".
            let last = Self.lastComponent(of: candidate.name)
            return last == titleSlug || (last.hasPrefix(titleSlug + "-") && Int(last.dropFirst(titleSlug.count + 1)) != nil)
        }
        // A commit only this branch is at: the task's own work. The checked-out branches count, so
        // a task that never committed (at its base's commit) isn't matched to some other branch.
        var byCheckpoint: [LegacyBranchCandidate] = []
        if let base, try await branchTips().filter({ $0 == base }).count == 1 {
            byCheckpoint = consistent.filter { $0.tip == base }
        }

        for matches in [byName, byTitle, byCheckpoint] where !matches.isEmpty {
            guard matches.count == 1, let branch = matches.first else {
                return .ambiguous(matches.map(\.name).sorted(), checkpoint: checkpoint)
            }
            return .found(ArchivedWorktree(path: path, branch: branch.name, checkpoint: checkpoint))
        }
        return .noBranch(checkpoint: checkpoint)
    }

    // MARK: - Helpers

    /// The newest checkpoint archiving made of the folder at `path`, no earlier than `archivedAt`.
    private func archiveCheckpoint(
        of path: URL, since archivedAt: Date?, isSameFolder: (String, String) -> Bool
    ) async throws(GitError) -> Checkpoint? {
        var spelling = path.standardizedFileURL.path(percentEncoded: false)
        if spelling.count > 1, spelling.hasSuffix("/") { spelling.removeLast() }
        let messagePrefix = "Native checkpoint of "
        let prefix = "refs/native-checkpoints/\(Worktree.slug(path.lastPathComponent, maxLength: 60))-"
        let output = try await run(
            [
                "for-each-ref", "--sort=-committerdate",
                "--format=%(refname)%00%(objectname)%00%(committerdate:unix)%00%(contents:subject)",
                "refs/native-checkpoints",
            ], readOnly: true)
        // Committer dates are whole seconds.
        let earliest = archivedAt.map { $0.timeIntervalSince1970.rounded(.down) } ?? 0
        for line in output.text.split(separator: "\n") {
            let fields = line.split(separator: "\0", omittingEmptySubsequences: false).map(String.init)
            guard fields.count == 4, fields[0].hasPrefix(prefix), fields[3].hasPrefix(messagePrefix),
                let time = Double(fields[2]), time >= earliest
            else { continue }
            var named = String(fields[3].dropFirst(messagePrefix.count))
            if named.count > 1, named.hasSuffix("/") { named.removeLast() }
            guard isSameFolder(spelling, named) else { continue }
            return Checkpoint(reference: fields[0], commit: fields[1])
        }
        return nil
    }

    /// Branches a removed task worktree could have been on: local ones no worktree has checked out,
    /// and copies of deleted ones whose name no local branch has taken since.
    private func legacyBranchCandidates() async throws(GitError) -> [LegacyBranchCandidate] {
        let checkedOut = Set(try await worktrees().compactMap(\.branch))
        let refs = try await run(
            ["for-each-ref", "--format=%(refname)%00%(objectname)", "refs/heads", "refs/native-archived-branches"],
            readOnly: true)
        var local: [LegacyBranchCandidate] = []
        var copies: [LegacyBranchCandidate] = []
        for line in refs.text.split(separator: "\n") {
            let fields = line.split(separator: "\0").map(String.init)
            guard fields.count == 2 else { continue }
            if fields[0].hasPrefix("refs/heads/") {
                let name = String(fields[0].dropFirst("refs/heads/".count))
                if !checkedOut.contains(name) {
                    local.append(LegacyBranchCandidate(name: name, tip: fields[1], isArchivedCopy: false))
                }
            } else {
                let name = String(fields[0].dropFirst("refs/native-archived-branches/".count))
                copies.append(LegacyBranchCandidate(name: name, tip: fields[1], isArchivedCopy: true))
            }
        }
        let taken = Set(local.map(\.name)).union(checkedOut)
        return local + copies.filter { !taken.contains($0.name) }
    }

    /// The commit each local branch is at, checked out or not.
    private func branchTips() async throws(GitError) -> [String] {
        try await run(["for-each-ref", "--format=%(objectname)", "refs/heads"], readOnly: true).text
            .split(separator: "\n").map(String.init)
    }

    /// The names `branch` had before git renamed it, from its reflog.
    private func renamedFrom(_ branch: String) async throws(GitError) -> [String] {
        let output = try await run(
            ["reflog", "show", "--format=%gs", "refs/heads/\(branch)", "--"], readOnly: true, acceptingStatus: [0, 128])
        return output.text.split(separator: "\n").compactMap { line in
            line.wholeMatch(of: /Branch: renamed refs\/heads\/(.+) to refs\/heads\/.+/).map { String($0.output.1) }
        }
    }

    /// Whether a task worktree folder named `folderName` was made for `branch`: a provisional
    /// branch ends in the folder's code, and a pull request's worktree is named after its branch.
    private static func isNamed(_ branch: String, after folderName: String) -> Bool {
        lastComponent(of: branch) == folderName || Worktree.slug(branch) == folderName
    }

    private static func lastComponent(of branch: String) -> String {
        branch.split(separator: "/").last.map(String.init) ?? branch
    }
}

private struct LegacyBranchCandidate {
    let name: String
    let tip: String
    /// A deleted branch's copy under `refs/native-archived-branches/`.
    let isArchivedCopy: Bool
}
