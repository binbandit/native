import Foundation

/// The pull request a workflow step opened. Its URL becomes the step's output.
nonisolated struct WorkflowPullRequestResult: Codable, Hashable, Sendable {
    var url: URL
    var number: Int?

    init(url: URL, number: Int? = nil) {
        self.url = url
        self.number = number
    }
}
