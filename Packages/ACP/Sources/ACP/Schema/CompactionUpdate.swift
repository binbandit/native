import Foundation

/// A context rewrite, whether requested by the user or started automatically by the agent.
public struct CompactionUpdate: Decodable, Sendable {
    public var compactionId: String
    public var status: Status
    public var summary: [ContentBlock]?
    public var error: String?

    public enum Status: Hashable, Sendable, Decodable {
        case inProgress, completed, failed, cancelled
        case unknown(String)

        public init(from decoder: any Decoder) throws {
            let value = try decoder.singleValueContainer().decode(String.self)
            self =
                switch value {
                case "in_progress": .inProgress
                case "completed": .completed
                case "failed": .failed
                case "cancelled": .cancelled
                default: .unknown(value)
                }
        }

        var toolStatus: ToolCallStatus? {
            switch self {
            case .inProgress: .inProgress
            case .completed: .completed
            case .failed: .failed
            case .cancelled: .cancelled
            case .unknown: nil
            }
        }
    }
}
