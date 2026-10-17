import Foundation

/// What an "open pull request" step fills in. Both fields are templates (`WorkflowTemplate`).
public nonisolated struct WorkflowPullRequestTemplate: Codable, Hashable, Sendable {
    public var title: String
    public var body: String
    public var isDraft: Bool

    public init(title: String = "{{title}}", body: String, isDraft: Bool = false) {
        self.title = title
        self.body = body
        self.isDraft = isDraft
    }

    private enum CodingKeys: String, CodingKey {
        case title, body, isDraft = "draft"
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? "{{title}}"
        body = try container.decode(String.self, forKey: .body)
        isDraft = try container.decodeIfPresent(Bool.self, forKey: .isDraft) ?? false
    }
}
