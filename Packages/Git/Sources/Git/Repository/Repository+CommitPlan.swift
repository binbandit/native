import Foundation

extension Repository {
    /// Makes the plan's commits in order, after checkpointing the uncommitted state. Each commit
    /// takes exactly its group's files. Stops at the first commit that fails (often a hook) and
    /// reports it alongside the commits already made, which `undo(_:)` can take back.
    public func commit(
        _ plan: CommitPlan, changes: [FileChange]
    ) async throws(GitError) -> (receipt: CommitPlanReceipt, failure: GitError?) {
        let branch = try await run(["symbolic-ref", "--quiet", "--short", "HEAD"], readOnly: true, acceptingStatus: [0, 1])
        var receipt = CommitPlanReceipt(
            branch: branch.status == 0 ? branch.text.trimmingCharacters(in: .whitespacesAndNewlines) : nil,
            originalHead: try await resolve("HEAD"),
            commits: [],
            checkpoint: try await checkpoint(named: "smart-commit")
        )
        for group in plan.groups {
            let paths = Set(group.paths)
            let files = changes.filter { !paths.isDisjoint(with: $0.paths) }
            do {
                receipt.commits.append(try await commit(message: group.message, files: files))
            } catch {
                return (receipt, error)
            }
        }
        return (receipt, nil)
    }

    /// Takes back a plan's commits: the branch goes back to where it was and the index to what was
    /// staged, while the files on disk stay as they are. Refused once anything else was committed
    /// on top, or the commits were pushed.
    public func undo(_ receipt: CommitPlanReceipt) async throws(GitError) {
        guard let last = receipt.commits.last else { return }
        guard try await resolve("HEAD") == last else {
            throw .failed(
                arguments: ["reset"], status: 1, stderr: "The branch has moved since those commits; undo them by hand.")
        }
        if let first = receipt.commits.first {
            let pushed = try await run(["branch", "--remotes", "--contains", first], readOnly: true)
            guard pushed.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw .failed(
                    arguments: ["reset"], status: 1,
                    stderr: "Those commits were pushed, so undoing them would rewrite shared history.")
            }
        }
        if let original = receipt.originalHead {
            try await run(["reset", "--soft", original])
        } else {
            // Before the first commit there's nothing to reset to: remove the branch's ref.
            try await run(["update-ref", "-d", "HEAD"])
        }
        if let checkpoint = receipt.checkpoint {
            try await restore(checkpoint, workingTree: false)
        }
    }
}
