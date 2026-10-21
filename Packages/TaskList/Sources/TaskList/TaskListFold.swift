import Foundation

/// Keeps recent resting tasks without changing the user's order. Attention, selection and editing
/// are supplied by the client, so folding never hides the task someone is working with.
/// `keeping` is activity outside the resting budget; `revealing` exposes selection or editing
/// without taking a recent resting task out of that budget.
public enum TaskListFold {
    public static func visibleIDs<ID: Hashable>(
        ordered: [ID], keeping: Set<ID>, dates: [ID: Date], revealing: Set<ID> = [], restingLimit: Int = 3
    ) -> Set<ID> {
        let resting = ordered.enumerated().filter { !keeping.contains($0.element) }
        let recent = resting.sorted {
            let lhs = dates[$0.element] ?? .distantPast
            let rhs = dates[$1.element] ?? .distantPast
            return lhs == rhs ? $0.offset < $1.offset : lhs > rhs
        }
        return keeping.union(recent.prefix(max(0, restingLimit)).map(\.element)).union(revealing)
    }
}
