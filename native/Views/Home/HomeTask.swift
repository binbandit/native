import Foundation

/// A recent task on the home page. `ID` is whatever the app selects tasks by.
public struct HomeTask<ID: Hashable>: Identifiable {
    public let id: ID
    public let title: String
    public let agentName: String
    public let agentSymbolName: String
    /// The task's project, when the list mixes projects.
    public let projectName: String?
    /// When the task was last active.
    public let date: Date?

    public init(
        id: ID, title: String, agentName: String, agentSymbolName: String, projectName: String? = nil, date: Date?
    ) {
        self.id = id
        self.title = title
        self.agentName = agentName
        self.agentSymbolName = agentSymbolName
        self.projectName = projectName
        self.date = date
    }
}
