import Foundation

extension Repository {
    /// Local branches, then remote-tracking ones, each most recently committed first.
    public func branches(includingRemote: Bool = true) async throws(GitError) -> [Branch] {
        // Ref names can't contain control characters, so one ref per line with NUL-separated
        // fields is unambiguous.
        let format = [
            "%(refname)", "%(refname:short)", "%(objectname)", "%(upstream:short)", "%(HEAD)", "%(committerdate:unix)",
            "%(worktreepath)", "%(symref)",
        ]
        .joined(separator: "%00")
        var arguments = ["for-each-ref", "--sort=-committerdate", "--format=\(format)", "refs/heads"]
        if includingRemote { arguments.append("refs/remotes") }
        let output = try await run(arguments, readOnly: true)
        return BranchParser.parse(output.text)
    }
}
