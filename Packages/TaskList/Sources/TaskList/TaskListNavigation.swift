/// Keeps the next available task open after an archive, falling back to the preceding task.
public enum TaskListNavigation {
    public static func successor<ID: Hashable>(to selected: ID, removing: Set<ID>, in order: [ID]) -> ID? {
        guard let index = order.firstIndex(of: selected) else { return nil }
        return order.suffix(from: index + 1).first { !removing.contains($0) }
            ?? order.prefix(index).last { !removing.contains($0) }
    }
}
