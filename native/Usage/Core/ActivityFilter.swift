import Foundation

/// Which part of the activity the graph shows.
enum ActivityFilter: Hashable {
    case all
    case agent(String)
    case project(String)

    func includes(_ entry: ActivityDay.Entry) -> Bool {
        switch self {
        case .all: true
        case .agent(let agent): entry.agent == agent
        case .project(let project): entry.project == project
        }
    }

    func includes(_ task: ActivityDay.Task) -> Bool {
        switch self {
        case .all: true
        case .agent(let agent): task.agent == agent
        case .project(let project): task.project == project
        }
    }
}
