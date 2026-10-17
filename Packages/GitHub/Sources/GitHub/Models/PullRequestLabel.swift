import Foundation

public struct PullRequestLabel: Sendable, Hashable, Decodable {
    public var name: String
    /// Six hex digits, without `#`.
    public var color: String?
    public var description: String?

    public init(name: String, color: String? = nil, description: String? = nil) {
        self.name = name
        self.color = color
        self.description = description
    }

    private enum CodingKeys: String, CodingKey {
        case name, color, description
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        color = try container.decodeText(forKey: .color)
        description = try container.decodeText(forKey: .description)
    }
}
