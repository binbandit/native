import Foundation

/// A pull request a workflow wants opened. The host hands it to the GitHub feature, which finds the
/// branch to open it from in `cwd` and pushes it if needed.
nonisolated struct WorkflowPullRequestDraft: Codable, Hashable, Sendable {
    var title: String
    var body: String
    var cwd: URL
    var isDraft: Bool
}
