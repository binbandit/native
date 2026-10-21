import Foundation
import Git

/// What the inspector compares when it isn't showing the uncommitted changes.
enum GitRangeRequest: Hashable {
    case turn(GitTurnReviewTarget)
    case branch
}

/// Where a comparison starts, and so how exact it is.
enum GitRangeBase: Hashable {
    /// The working tree as the turn began, recorded then: exactly the turn's changes.
    case turnSnapshot
    /// HEAD as it was when the turn began, for a turn whose start wasn't recorded: changes that
    /// weren't committed then show too.
    case turnStartCommit(Date)
    /// Where the branch left the default branch, or on the default branch, its upstream.
    case branch(BranchBase)
    /// Nothing earlier to compare with, so HEAD: only the uncommitted changes show.
    case head
}

/// Everything that changed from a base to the working tree now, committed or not.
struct GitRangeComparison: Equatable {
    let request: GitRangeRequest
    let base: GitRangeBase
    /// git's id for the base side, a tree or a commit; nil for the empty tree.
    let baseID: String?
    /// The working tree now, as a snapshot's tree.
    let target: String
    let changes: [TreeChange]
    /// For a turn, the files its card lists, relative to the repository's root.
    let editedPaths: Set<String>

    var totals: LineStats {
        changes.compactMap(\.stats).reduce(.zero, +)
    }

    /// The changes to files listed by the turn's card.
    var edited: [TreeChange] {
        changes.filter(isEdited)
    }

    /// Everything else: what commands changed, or other work in the same folder.
    var others: [TreeChange] {
        changes.filter { !isEdited($0) }
    }

    /// Files from the turn's card that are back to how they were at the base.
    var undone: [String] {
        let changed = Set(changes.flatMap(\.paths))
        return editedPaths.subtracting(changed).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    var isTurn: Bool {
        if case .turn = request { true } else { false }
    }

    /// Whether the base is the turn's own start, recorded or not, rather than the branch's.
    var startsAtTurn: Bool {
        switch base {
        case .turnSnapshot, .turnStartCommit: true
        case .branch, .head: false
        }
    }

    private func isEdited(_ change: TreeChange) -> Bool {
        change.paths.contains(where: editedPaths.contains)
    }
}
