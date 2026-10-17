import Foundation

extension Repository {
    /// Commits what's staged, running the user's hooks and signing setup, and returns the new
    /// commit's id. With `files`, the index is first made to hold exactly those changes: they're
    /// staged in full and anything else staged is unstaged.
    @discardableResult
    public func commit(message: String, files: [FileChange]? = nil) async throws(GitError) -> String {
        if let files {
            let selected = Set(files.flatMap(\.paths))
            try await stage(Array(selected).sorted())
            let status = try await run(["status", "--porcelain=v2", "-z", "--untracked-files=no"], readOnly: true)
            let stagedElsewhere = try StatusParser.parse(status.text).changes
                .filter { $0.area == .staged && selected.isDisjoint(with: $0.paths) }
                .flatMap(\.paths)
            try await unstage(stagedElsewhere)
        }
        try await run(["commit", "--file=-"], input: Data(message.utf8))
        let head = try await run(["rev-parse", "HEAD"], readOnly: true)
        return head.text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Pushes the current branch, setting its upstream on the push remote when it has none.
    public func push() async throws(GitError) {
        let branchOutput = try await run(["symbolic-ref", "--quiet", "--short", "HEAD"], readOnly: true, acceptingStatus: [0, 1])
        guard branchOutput.status == 0 else { throw .detachedHead }
        let branch = branchOutput.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let upstream = try await run(["rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{upstream}"], readOnly: true, acceptingStatus: [0, 128])
        if upstream.status == 0 {
            try await run(["push"])
            return
        }
        let remote = try await pushRemote(for: branch)
        try await run(["push", "--set-upstream", remote, "HEAD:refs/heads/\(branch)"])
    }

    /// Pulls the current branch's upstream, merging or rebasing as the user's `pull.rebase` says.
    /// Like `push()`, this talks to the network, so it only runs when the user asks.
    public func pull() async throws(GitError) {
        try await run(["pull", "--no-edit"])
    }

    /// Where a branch without an upstream should go: its push remote, the default push remote,
    /// `origin`, or the only remote there is.
    private func pushRemote(for branch: String) async throws(GitError) -> String {
        for key in ["branch.\(branch).pushRemote", "remote.pushDefault"] {
            let value = try await run(["config", "--get", key], readOnly: true, acceptingStatus: [0, 1])
            let remote = value.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if value.status == 0, !remote.isEmpty { return remote }
        }
        let remotes = try await remotes()
        if remotes.contains("origin") { return "origin" }
        guard let first = remotes.first else { throw .noRemote }
        return first
    }

    /// The names of the configured remotes, e.g. `["origin"]`.
    public func remotes() async throws(GitError) -> [String] {
        try await run(["remote"], readOnly: true).text.split(separator: "\n").map(String.init)
    }

    // MARK: - History

    /// Subjects of the latest commits, newest first, e.g. to match a repository's message style.
    public func recentCommitSubjects(limit: Int = 20) async throws(GitError) -> [String] {
        let output = try await run(["log", "-n", "\(limit)", "--no-merges", "--format=%s%x00"], readOnly: true, acceptingStatus: [0, 128])
        // 128: no commits yet.
        guard output.status == 0 else { return [] }
        return output.text
            .split(separator: "\0")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}
