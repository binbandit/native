import Foundation

/// A pull request a workflow wants opened. The host hands it to the GitHub feature, which finds the
/// branch to open it from in `cwd` and pushes it if needed.
public nonisolated struct WorkflowPullRequestDraft: Codable, Hashable, Sendable {
    public var title: String
    public var body: String
    public var cwd: URL
    public var isDraft: Bool

    public init(title: String, body: String, cwd: URL, isDraft: Bool) {
        self.title = title
        self.body = body
        self.cwd = cwd
        self.isDraft = isDraft
    }
}
