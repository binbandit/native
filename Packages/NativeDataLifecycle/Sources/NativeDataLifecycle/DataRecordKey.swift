/// What one record in a store is about, so a request or a hold can name it.
public enum DataRecordScope: String, CaseIterable, Codable, Sendable {
    /// A task: one agent session and what Native keeps for it.
    case session
    case project
    case repository
    case pullRequest
    case automation
    case expedition
    case skill
    case plugin
    case agent
    case device
    case host
    case approval
    /// The store as a whole (a cache or a log without per-task records).
    case store
}

/// One logical record. The id is the owner's own opaque identifier (a session id, a project id),
/// never a path, title or other content.
public struct DataRecordKey: Hashable, Codable, Comparable, Sendable, CustomStringConvertible {
    public var scope: DataRecordScope
    public var id: String

    public init(_ scope: DataRecordScope, _ id: String) {
        self.scope = scope
        self.id = id
    }

    public var description: String { "\(scope.rawValue):\(id)" }

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.description < rhs.description }
}
