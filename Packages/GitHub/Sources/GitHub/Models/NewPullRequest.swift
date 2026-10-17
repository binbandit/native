import Foundation

/// What `gh pr create` needs. The head branch must already be pushed: `--head` is always passed,
/// so gh never pushes on its own.
public struct NewPullRequest: Sendable, Hashable {
    public var title: String
    public var body: String
    /// The branch with the changes.
    public var head: String
    /// The branch to merge into; `nil` for the repository's default branch.
    public var base: String?
    public var isDraft: Bool

    public init(title: String, body: String, head: String, base: String? = nil, isDraft: Bool = false) {
        self.title = title
        self.body = body
        self.head = head
        self.base = base
        self.isDraft = isDraft
    }
}
