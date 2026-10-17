import Foundation

/// A gate before a step: the run waits until the user approves it, and they can edit the step's
/// prompt first. JSON: `"approval": true`, or `"approval": "<what to check>"`, or an object.
public nonisolated struct WorkflowApproval: Hashable, Sendable {
    /// What the user should check before approving.
    public var message: String?

    public init(message: String? = nil) {
        self.message = message
    }
}

extension WorkflowApproval: Codable {
    private enum CodingKeys: String, CodingKey {
        case message
    }

    public init(from decoder: any Decoder) throws {
        if let message = try? decoder.singleValueContainer().decode(String.self) {
            self.message = message
        } else {
            message = try decoder.container(keyedBy: CodingKeys.self).decodeIfPresent(String.self, forKey: .message)
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        if let message {
            try container.encode(message)
        } else {
            try container.encode(true)
        }
    }
}
