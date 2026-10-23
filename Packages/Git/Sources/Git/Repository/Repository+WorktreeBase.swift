import Foundation

extension Repository {
    /// Pins a new task's base without moving the project's checkout. Only this fetch opts into
    /// network access; callers must pass their managed policy. A failed fetch uses the local tip.
    public func taskWorktreeBase(fetchRemote: Bool) async throws(GitError) -> TaskWorktreeBase {
        let branch = try await currentBranchName()
        guard let local = try await resolve("HEAD") else {
            throw .unexpectedOutput("The repository has no commits yet.")
        }
        guard fetchRemote else { return TaskWorktreeBase(commit: local, branch: branch, source: .local(.disabled)) }
        guard let branch else { return TaskWorktreeBase(commit: local, branch: nil, source: .local(.detached)) }
        let configuredRemote = try await branchConfig(branch, key: "remote")
        let merge = try await branchConfig(branch, key: "merge")
        let remotes = try await remoteURLs().map(\.name)
        let remote = configuredRemote ?? (remotes.contains("origin") ? "origin" : remotes.count == 1 ? remotes[0] : nil)
        guard let remote, remote != ".", remotes.contains(remote) else {
            return TaskWorktreeBase(commit: local, branch: branch, source: .local(.noRemote))
        }
        let ref = merge ?? "refs/heads/\(branch)"
        guard ref.hasPrefix("refs/heads/") else {
            return TaskWorktreeBase(commit: local, branch: branch, source: .local(.noRemote))
        }
        // A private ref avoids races with other fetches, including ones outside Native. Capture its
        // commit before removing it, so the later checkout cannot follow a moving remote ref.
        let fetched = "refs/native/worktree-bases/\(UUID().uuidString)"
        let base: TaskWorktreeBase
        do {
            try await git.run(
                [
                    "fetch", "--no-tags", "--no-recurse-submodules", "--no-write-fetch-head", "--", remote,
                    "+\(ref):\(fetched)",
                ],
                in: root, lowPriority: true, timeout: .seconds(15),
                environment: [
                    "GIT_ASKPASS": "/usr/bin/false", "SSH_ASKPASS": "/usr/bin/false", "GCM_INTERACTIVE": "never",
                ])
            guard let commit = try await resolve(fetched) else {
                throw GitError.unexpectedOutput("The fetched branch has no commit.")
            }
            base = TaskWorktreeBase(commit: commit, branch: branch, source: .remote)
        } catch {
            base = TaskWorktreeBase(commit: local, branch: branch, source: .local(.fetchFailed))
        }
        await Task { _ = try? await run(["update-ref", "-d", fetched]) }.value
        if Task.isCancelled { throw .cancelled }
        return base
    }

    private func branchConfig(_ branch: String, key: String) async throws(GitError) -> String? {
        let output = try await run(
            ["config", "--get", "branch.\(branch).\(key)"], readOnly: true, acceptingStatus: [0, 1])
        let value = output.text.trimmingCharacters(in: .whitespacesAndNewlines)
        return output.status == 0 && !value.isEmpty ? value : nil
    }
}
