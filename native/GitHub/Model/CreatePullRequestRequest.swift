import Foundation

/// A pushed branch the user wants a pull request for. The Git feature supplies it from its commit
/// UI (through the app), with the material the AI draft is written from.
struct CreatePullRequestRequest: Identifiable, Hashable, Sendable {
    let id = UUID()
    /// The checkout the branch lives in.
    var directory: URL
    var head: String
    /// `nil` for the repository's default branch.
    var base: String?
    /// `git log base..head` output, newest first.
    var commits: String
    /// `git diff base...head`, if the caller has it.
    var diff: String?
    /// The repository's pull request template (`.github/pull_request_template.md` and the other
    /// places GitHub looks), read on the machine that hosts the checkout.
    var template: String?

    init(
        directory: URL, head: String, base: String? = nil, commits: String, diff: String? = nil, template: String? = nil
    ) {
        self.directory = directory
        self.head = head
        self.base = base
        self.commits = commits
        self.diff = diff
        self.template = template
    }

    var branch: BranchReference {
        BranchReference(directory: directory, branch: head)
    }
}
