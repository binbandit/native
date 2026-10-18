import Foundation

/// One local calendar day of activity, broken down by agent and project, with the tasks touched.
struct ActivityDay: Codable, Hashable {
    struct Entry: Codable, Hashable {
        let agent: String
        let agentName: String
        /// The project's folder path.
        let project: String
        var counts = ActivityCounts()
    }

    struct Task: Codable, Hashable, Identifiable {
        let agent: String
        let agentName: String
        let session: String
        var title: String?
        let project: String

        var id: String { "\(agent)/\(session)" }
    }

    /// The day in the calendar it was recorded in, "2026-10-18", so a later time-zone change never
    /// moves it.
    let day: String
    var entries: [Entry] = []
    var tasks: [Task] = []

    mutating func add(_ counts: ActivityCounts, agent: String, agentName: String, project: String) {
        if let index = entries.firstIndex(where: { $0.agent == agent && $0.project == project }) {
            entries[index].counts = entries[index].counts + counts
        } else {
            entries.append(Entry(agent: agent, agentName: agentName, project: project, counts: counts))
        }
    }

    mutating func touch(_ task: Task) {
        if let index = tasks.firstIndex(where: { $0.id == task.id }) {
            tasks[index].title = task.title ?? tasks[index].title
        } else {
            tasks.append(task)
        }
    }
}
