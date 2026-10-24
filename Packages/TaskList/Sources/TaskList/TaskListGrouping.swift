/// Archive groups follow project order while preserving each project's task order. Archived
/// projects remain visible even when they have no individually archived tasks.
public enum TaskListGrouping {
    public struct Group<Project: Hashable, Item> {
        public let project: Project
        public let tasks: [Item]
        public let isArchivedProject: Bool
    }

    public static func archive<Project: Hashable, Item>(
        projects: [Project], archivedProjects: [Project], tasks: [Item], project: (Item) -> Project
    ) -> [Group<Project, Item>] {
        let byProject = Dictionary(grouping: tasks, by: project)
        let archived = Set(archivedProjects)
        return (projects + archivedProjects).compactMap { id in
            let tasks = byProject[id] ?? []
            guard !tasks.isEmpty || archived.contains(id) else { return nil }
            return Group(project: id, tasks: tasks, isArchivedProject: archived.contains(id))
        }
    }
}
