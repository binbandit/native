import Foundation

/// A task's identity across every agent session that takes part in it. The host allocates it and
/// keeps the task's history under it; agent session ids only point at it
/// (docs/decisions/2026-11-01-one-task-history.md).
public struct TaskHistoryID: Hashable, Sendable, Codable, CustomStringConvertible {
    public let rawValue: UUID

    public init(_ rawValue: UUID = UUID()) {
        self.rawValue = rawValue
    }

    public init(from decoder: any Decoder) throws {
        rawValue = try decoder.singleValueContainer().decode(UUID.self)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    public var description: String { rawValue.uuidString }
}
