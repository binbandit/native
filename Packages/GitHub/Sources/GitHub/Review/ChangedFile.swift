import Foundation

/// A file a pull request changes, as GraphQL lists them: its counts and whether the viewer has
/// marked it viewed. GitHub keeps that mark per user and clears it (`dismissed`) when the file
/// changes again.
public struct ChangedFile: Sendable, Hashable, Identifiable, Decodable {
    public enum ChangeType: String, Sendable, Hashable, GitHubEnum {
        case added = "ADDED"
        case deleted = "DELETED"
        case renamed = "RENAMED"
        case copied = "COPIED"
        case modified = "MODIFIED"
        case changed = "CHANGED"
        case other
    }

    public enum ViewedState: String, Sendable, Hashable, GitHubEnum {
        case viewed = "VIEWED"
        case unviewed = "UNVIEWED"
        /// Viewed, then changed by a later push.
        case dismissed = "DISMISSED"
        case other
    }

    public var path: String
    public var additions: Int
    public var deletions: Int
    public var changeType: ChangeType
    public var viewedState: ViewedState

    public var id: String { path }

    public var isViewed: Bool {
        viewedState == .viewed
    }

    /// Lockfiles, build output and the like, which GitHub folds by default.
    public var isGenerated: Bool {
        GeneratedFiles.isGenerated(path)
    }

    public init(
        path: String, additions: Int, deletions: Int, changeType: ChangeType,
        viewedState: ViewedState = .unviewed
    ) {
        self.path = path
        self.additions = additions
        self.deletions = deletions
        self.changeType = changeType
        self.viewedState = viewedState
    }

    private enum CodingKeys: String, CodingKey {
        case path, additions, deletions, changeType, viewerViewedState
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        path = try container.decode(String.self, forKey: .path)
        additions = try container.decodeIfPresent(Int.self, forKey: .additions) ?? 0
        deletions = try container.decodeIfPresent(Int.self, forKey: .deletions) ?? 0
        changeType = try container.decodeEnum(ChangeType.self, forKey: .changeType) ?? .other
        viewedState =
            try container.decodeEnum(ViewedState.self, forKey: .viewerViewedState) ?? .unviewed
    }
}
