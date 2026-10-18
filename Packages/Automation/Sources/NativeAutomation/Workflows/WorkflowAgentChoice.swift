import Foundation

/// Which agent a step asks for. Workflows name agents relative to each other where they can
/// ("a different agent than the implementer") so a definition works with whatever agents the user
/// has, and the point of a cross-provider review survives a change of default agent.
///
/// JSON: `"codex"`, `{"sameAs": "plan"}` or `{"differentFrom": "implement"}`. Omitted means the
/// run's default agent.
public nonisolated enum WorkflowAgentChoice: Hashable, Sendable {
    /// A specific agent by id; falls back to the default when it isn't available.
    case agent(String)
    case sameAs(String)
    /// Falls back to the same agent, with a note, when only one agent is available.
    case differentFrom(String)

    /// The step this choice depends on, if any.
    public var referencedStep: String? {
        switch self {
        case .agent: nil
        case .sameAs(let step), .differentFrom(let step): step
        }
    }
}

extension WorkflowAgentChoice: Codable {
    private enum CodingKeys: String, CodingKey {
        case sameAs, differentFrom
    }

    public init(from decoder: any Decoder) throws {
        if let id = try? decoder.singleValueContainer().decode(String.self) {
            self = .agent(id)
            return
        }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let step = try container.decodeIfPresent(String.self, forKey: .sameAs) {
            self = .sameAs(step)
        } else if let step = try container.decodeIfPresent(String.self, forKey: .differentFrom) {
            self = .differentFrom(step)
        } else {
            throw DecodingError.dataCorrupted(
                .init(
                    codingPath: decoder.codingPath,
                    debugDescription: "An agent is an agent id, {\"sameAs\": step} or {\"differentFrom\": step}."
                ))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        switch self {
        case .agent(let id):
            var container = encoder.singleValueContainer()
            try container.encode(id)
        case .sameAs(let step):
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(step, forKey: .sameAs)
        case .differentFrom(let step):
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(step, forKey: .differentFrom)
        }
    }
}
