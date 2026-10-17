import Foundation

/// The signed-in user, from `gh api user`.
public struct GitHubUser: Sendable, Hashable, Decodable {
    public var login: String
    public var name: String?
    public var avatarURL: URL?
    public var profileURL: URL?

    public init(login: String, name: String? = nil, avatarURL: URL? = nil, profileURL: URL? = nil) {
        self.login = login
        self.name = name
        self.avatarURL = avatarURL
        self.profileURL = profileURL
    }

    private enum CodingKeys: String, CodingKey {
        case login, name
        case avatarURL = "avatar_url"
        case profileURL = "html_url"
    }
}
