/// Groups only visible tasks. A filtered or archived parent never hides its assigned tasks.
public enum CoordinatorOrdering {
    public static func grouped<ID: Hashable>(_ groups: [[ID]], assignments: [ID: [ID]]) -> [[ID]] {
        let visible = Set(groups.flatMap { $0 })
        let parents = assignments.filter { visible.contains($0.key) }
        let children = Set(parents.values.flatMap { $0 }).intersection(visible)
        return groups.map { group in
            group.filter { !children.contains($0) }.flatMap { id in
                [id] + (parents[id] ?? []).filter { visible.contains($0) }
            }
        }
    }
}
