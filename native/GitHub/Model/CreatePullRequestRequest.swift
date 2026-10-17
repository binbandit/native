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

    init(directory: URL, head: String, base: String? = nil, commits: String, diff: String? = nil) {
        self.directory = directory
        self.head = head
        self.base = base
        self.commits = commits
        self.diff = diff
    }

    var branch: BranchReference {
        BranchReference(directory: directory, branch: head)
    }

    /// The repository's pull request template, in the places GitHub looks for one.
    func template() -> String? {
        let candidates = [
            ".github/pull_request_template.md", ".github/PULL_REQUEST_TEMPLATE.md",
            "pull_request_template.md", "PULL_REQUEST_TEMPLATE.md",
            "docs/pull_request_template.md", "docs/PULL_REQUEST_TEMPLATE.md",
        ]
        for path in candidates {
            if let text = try? String(contentsOf: directory.appending(path: path), encoding: .utf8) {
                return text
            }
        }
        return nil
    }
}
