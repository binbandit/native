import Foundation

/// A repository as `gh repo view --json` describes it.
public struct GitHubRepository: Sendable, Hashable, Decodable {
    public var name: String
    /// `owner/name`, the key pull requests are grouped by.
    public var nameWithOwner: String
    public var url: URL
    public var defaultBranch: String?
    public var isPrivate: Bool
    public var isFork: Bool
    public var description: String?
    /// ADMIN, MAINTAIN, WRITE, TRIAGE or READ.
    public var viewerPermission: String?

    public init(
        name: String, nameWithOwner: String, url: URL, defaultBranch: String? = nil, isPrivate: Bool = false,
        isFork: Bool = false, description: String? = nil, viewerPermission: String? = nil
    ) {
        self.name = name
        self.nameWithOwner = nameWithOwner
        self.url = url
        self.defaultBranch = defaultBranch
        self.isPrivate = isPrivate
        self.isFork = isFork
        self.description = description
        self.viewerPermission = viewerPermission
    }

    static let fields = "name,nameWithOwner,url,defaultBranchRef,isPrivate,isFork,description,viewerPermission"

    private enum CodingKeys: String, CodingKey {
        case name, nameWithOwner, url, defaultBranchRef, isPrivate, isFork, description, viewerPermission
    }

    private struct BranchRef: Decodable {
        var name: String
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        nameWithOwner = try container.decode(String.self, forKey: .nameWithOwner)
        url = try container.decode(URL.self, forKey: .url)
        // An empty repository has no default branch, which gh prints as `{"name": ""}`.
        defaultBranch = try container.decodeIfPresent(BranchRef.self, forKey: .defaultBranchRef)
            .flatMap { $0.name.isEmpty ? nil : $0.name }
        isPrivate = try container.decodeIfPresent(Bool.self, forKey: .isPrivate) ?? false
        isFork = try container.decodeIfPresent(Bool.self, forKey: .isFork) ?? false
        description = try container.decodeText(forKey: .description)
        viewerPermission = try container.decodeText(forKey: .viewerPermission)
    }
}
