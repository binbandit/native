/// Which changes the inspector shows: the latest turn's, committed or not; the uncommitted ones,
/// which it can stage, commit and discard; or everything on the branch.
enum GitChangesScope: Hashable, CaseIterable {
    case turn
    case uncommitted
    case branch

    /// The picker's label.
    var title: String {
        switch self {
        case .turn: "This Turn"
        case .uncommitted: "Uncommitted"
        case .branch: "Branch"
        }
    }
}
