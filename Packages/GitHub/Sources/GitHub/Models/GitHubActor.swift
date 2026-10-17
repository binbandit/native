import Foundation

/// A user or app: a pull request's author, a reviewer, an assignee.
public struct GitHubActor: Sendable, Hashable, Decodable {
    public var login: String
    public var isBot: Bool

    public init(login: String, isBot: Bool = false) {
        self.login = login
        self.isBot = isBot
    }

    private enum CodingKeys: String, CodingKey {
        case login, isBot = "is_bot", type
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        login = try container.decode(String.self, forKey: .login)
        // `gh search` reports apps with `is_bot: false`, but `type: "Bot"` and a `[bot]` login;
        // `gh pr view` reports them as `app/<name>`.
        let type = try container.decodeIfPresent(String.self, forKey: .type)
        isBot =
            try container.decodeIfPresent(Bool.self, forKey: .isBot) == true
            || type == "Bot" || login.hasSuffix("[bot]") || login.hasPrefix("app/")
    }
}
