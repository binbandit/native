/// Names an experiment. It's also the experiment's storage key, so it never changes once shipped.
public struct ExperimentID: Hashable, Sendable, CustomStringConvertible, ExpressibleByStringLiteral {
    public let rawValue: String

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    public init(stringLiteral value: String) {
        self.init(value)
    }

    public var description: String { rawValue }
}

/// How far along an experiment is.
public enum ExperimentStage: Int, Hashable, Sendable, CaseIterable, Comparable {
    /// Early and rough: it may change a lot or go away.
    case labs
    /// Close to done: it's being tried before it becomes the default.
    case beta

    public var title: String {
        switch self {
        case .labs: "Labs"
        case .beta: "Beta"
        }
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}
