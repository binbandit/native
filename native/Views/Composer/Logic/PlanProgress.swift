import ACP

/// The agent's plan as the composer shows it, after the reference app's plan visualizer.
struct PlanProgress: Equatable {
    let entries: [PlanEntry]

    /// Shown only while there's something left to do.
    var isActive: Bool {
        entries.contains { $0.status != .completed }
    }

    var completedCount: Int {
        entries.count { $0.status == .completed }
    }

    /// Collapsed, only the step in progress shows, or failing that the next one.
    func visibleEntries(isExpanded: Bool) -> [PlanEntry] {
        guard !isExpanded else { return entries }
        let current = entries.filter { $0.status == .inProgress }
        if !current.isEmpty { return current }
        return (entries.first { $0.status == .pending } ?? entries.first).map { [$0] } ?? []
    }
}
