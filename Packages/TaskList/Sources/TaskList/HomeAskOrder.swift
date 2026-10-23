import Foundation

/// Home triage: approvals take one decision, then questions, plans, and recovery work.
/// An ask already being read keeps its place until answered, even if another arrives.
public enum HomeAskOrder: String, CaseIterable, Sendable {
    case quickest, oldest

    public enum Kind: Int, Sendable {
        case approval, question, plan, failure, limit
    }

    /// A task can contain several simultaneous asks from its parent and child sessions.
    public static func first<Element, ID: Equatable>(
        _ elements: [Element], retaining current: ID?, id: (Element) -> ID
    ) -> Element? {
        if let current, let retained = elements.first(where: { id($0) == current }) { return retained }
        return elements.first
    }

    public func sorted<Element, ID: Hashable>(
        _ elements: [Element], retaining current: ID? = nil,
        id: (Element) -> ID, kind: (Element) -> Kind, date: (Element) -> Date?
    ) -> [Element] {
        elements.enumerated().sorted { lhs, rhs in
            if let current {
                let left = id(lhs.element) == current, right = id(rhs.element) == current
                if left != right { return left }
            }
            if self == .quickest, kind(lhs.element) != kind(rhs.element) {
                return kind(lhs.element).rawValue < kind(rhs.element).rawValue
            }
            let left = date(lhs.element) ?? .distantFuture, right = date(rhs.element) ?? .distantFuture
            return left == right ? lhs.offset < rhs.offset : left < right
        }.map(\.element)
    }
}
