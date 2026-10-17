import Foundation

/// What a workflow asks the user for before it runs; it reaches prompts as `{{input}}`.
public nonisolated struct WorkflowInput: Codable, Hashable, Sendable {
    public var label: String
    public var placeholder: String?
    public var isRequired: Bool

    public init(label: String = "What should it do?", placeholder: String? = nil, isRequired: Bool = true) {
        self.label = label
        self.placeholder = placeholder
        self.isRequired = isRequired
    }

    private enum CodingKeys: String, CodingKey {
        case label, placeholder, isRequired = "required"
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        label = try container.decodeIfPresent(String.self, forKey: .label) ?? "What should it do?"
        placeholder = try container.decodeIfPresent(String.self, forKey: .placeholder)
        isRequired = try container.decodeIfPresent(Bool.self, forKey: .isRequired) ?? true
    }
}
