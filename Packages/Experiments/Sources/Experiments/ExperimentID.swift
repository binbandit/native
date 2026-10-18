/// Names an experiment. It's also the experiment's storage key, so it never changes once shipped.
public struct ExperimentID: Hashable, Sendable, CustomStringConvertible, ExpressibleByStringLiteral {
    public let rawValue: String

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    public init(stringLiteral value: String) {
        self.init(value)
    }

    /// A plugin's experiment: `name` prefixed with the plugin's id, so plugins' ids never collide
    /// with Native's or each other's (`acme.fast-mode`).
    public init(namespace: String, _ name: String) {
        self.init("\(namespace).\(name)")
    }

    /// Whether the id is in a plugin's namespace.
    public func isNamespaced(by namespace: String) -> Bool {
        rawValue.hasPrefix("\(namespace).") && rawValue.count > namespace.count + 1
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
