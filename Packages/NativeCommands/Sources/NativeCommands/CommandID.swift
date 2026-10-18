/// A command's stable name, such as `session.archive`: what preferences, exported shortcut files,
/// configuration profiles and `docs/keyboard.md` call it. Never rename one; add a new id instead.
public struct CommandID: RawRepresentable, Hashable, Comparable, Sendable, Codable, ExpressibleByStringLiteral {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    public init(stringLiteral value: String) {
        rawValue = value
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

extension CommandID: CustomStringConvertible {
    public var description: String { rawValue }
}
