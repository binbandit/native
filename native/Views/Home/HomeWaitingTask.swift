import Foundation

/// A task waiting on the user, for the home page's Needs You strip. `ID` is whatever the app
/// selects tasks by.
public struct HomeWaitingTask<ID: Hashable>: Identifiable {
    public let id: ID
    public let title: String
    /// What it's asking, in a line: "Run `npm test`?", "Which palette should the hero use?".
    public let request: String
    /// One of the statuses that need the user: input, permission or a plan to review.
    public let status: TaskStatus
    public let agentName: String

    public init(id: ID, title: String, request: String, status: TaskStatus, agentName: String) {
        self.id = id
        self.title = title
        self.request = request
        self.status = status
        self.agentName = agentName
    }
}
