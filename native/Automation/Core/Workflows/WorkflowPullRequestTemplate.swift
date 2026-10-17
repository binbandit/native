import Foundation

/// What an "open pull request" step fills in. Both fields are templates (`WorkflowTemplate`).
nonisolated struct WorkflowPullRequestTemplate: Codable, Hashable, Sendable {
    var title: String
    var body: String
    var isDraft: Bool

    init(title: String = "{{title}}", body: String, isDraft: Bool = false) {
        self.title = title
        self.body = body
        self.isDraft = isDraft
    }

    private enum CodingKeys: String, CodingKey {
        case title, body, isDraft = "draft"
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? "{{title}}"
        body = try container.decode(String.self, forKey: .body)
        isDraft = try container.decodeIfPresent(Bool.self, forKey: .isDraft) ?? false
    }
}
