import Foundation

/// The pull request a workflow step opened. Its URL becomes the step's output.
public nonisolated struct WorkflowPullRequestResult: Codable, Hashable, Sendable {
    public var url: URL
    public var number: Int?

    public init(url: URL, number: Int? = nil) {
        self.url = url
        self.number = number
    }
}
