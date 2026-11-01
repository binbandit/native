import Foundation
import TaskList

/// The archive follows the project's order, with its tasks kept underneath their owner.
struct ArchivedTaskGroup: Identifiable {
    let project: Project
    let tasks: [SessionSummary]
    let isArchivedProject: Bool
    var id: Project.ID { project.id }
}

extension AppModel {
    var archivedTaskGroups: [ArchivedTaskGroup] {
        let ordered = taskGroups + projects.archived
        let lookup = Dictionary(uniqueKeysWithValues: ordered.map { ($0.id, $0) })
        return TaskListGrouping.archive(
            projects: taskGroups.map(\.id), archivedProjects: projects.archived.map(\.id),
            tasks: ordered.flatMap { archivedSessions(in: $0.id) }, project: \.project
        ).compactMap { group in
            guard let project = lookup[group.project] else { return nil }
            return ArchivedTaskGroup(project: project, tasks: group.tasks, isArchivedProject: group.isArchivedProject)
        }
    }
}
