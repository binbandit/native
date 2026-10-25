import Observation

/// Each window can open earlier tasks without changing their saved order or dates.
@Observable
final class SidebarDayFolding {
    private var expanded: Set<Project.ID> = []

    func isExpanded(_ project: Project.ID) -> Bool { expanded.contains(project) }

    func setExpanded(_ project: Project.ID, _ value: Bool) {
        if value { expanded.insert(project) } else { expanded.remove(project) }
    }
}
