import Foundation

/// A session as the engine names it for good: the agent it runs on and the agent's own id for it.
/// That outlives a launch, a host restart, and the session being closed and opened again under
/// another of Native's ids.
public struct TaskSessionRef: Hashable, Codable, Sendable, CustomStringConvertible {
    public var agent: String
    public var id: String

    public init(agent: String, id: String) {
        self.agent = agent
        self.id = id
    }

    public var description: String { "\(agent)/\(id)" }

    private enum CodingKeys: String, CodingKey {
        case agent, id
    }

    private enum WrappedKeys: String, CodingKey {
        case rawValue
    }

    /// Records the app saved before the engine was a package name the agent `{"rawValue": …}`.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        if let agent = try? container.decode(String.self, forKey: .agent) {
            self.agent = agent
        } else {
            agent = try container.nestedContainer(keyedBy: WrappedKeys.self, forKey: .agent)
                .decode(String.self, forKey: .rawValue)
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(agent, forKey: .agent)
        try container.encode(id, forKey: .id)
    }
}
