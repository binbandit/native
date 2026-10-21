/// A window's current task order, including its filters and sorting. The model holds this weakly
/// so retaining undo history does not keep the sidebar and its feature services alive.
@MainActor
protocol ArchiveNavigationOrdering: AnyObject {
    func archiveSessionOrder() -> [SessionKey]
}
