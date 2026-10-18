import Foundation

/// A conversation on a diff line or range: its anchor, whether it's resolved or outdated, and its
/// comments, oldest first.
public struct ReviewThread: Sendable, Hashable, Identifiable, Decodable {
    public var id: String
    public var path: String
    public var isResolved: Bool
    /// The lines it was written on have changed since; GitHub keeps it at its original position.
    public var isOutdated: Bool
    /// The line on the current diff; `nil` when outdated.
    public var line: Int?
    public var startLine: Int?
    public var originalLine: Int?
    public var side: DiffSide
    public var startSide: DiffSide?
    /// Comments on the whole file rather than a line.
    public var isFileLevel: Bool
    public var viewerCanResolve: Bool
    public var viewerCanUnresolve: Bool
    public var viewerCanReply: Bool
    public var resolvedBy: String?
    public var comments: [ReviewComment]

    public init(
        id: String, path: String, isResolved: Bool = false, isOutdated: Bool = false, line: Int?,
        startLine: Int? = nil,
        originalLine: Int? = nil, side: DiffSide = .right, startSide: DiffSide? = nil,
        isFileLevel: Bool = false,
        viewerCanResolve: Bool = false, viewerCanUnresolve: Bool = false, viewerCanReply: Bool = true,
        resolvedBy: String? = nil, comments: [ReviewComment]
    ) {
        self.id = id
        self.path = path
        self.isResolved = isResolved
        self.isOutdated = isOutdated
        self.line = line
        self.startLine = startLine
        self.originalLine = originalLine
        self.side = side
        self.startSide = startSide
        self.isFileLevel = isFileLevel
        self.viewerCanResolve = viewerCanResolve
        self.viewerCanUnresolve = viewerCanUnresolve
        self.viewerCanReply = viewerCanReply
        self.resolvedBy = resolvedBy
        self.comments = comments
    }

    /// Only in the viewer's pending review so far.
    public var isPending: Bool {
        !comments.isEmpty && comments.allSatisfy(\.isPending)
    }

    /// Where it's drawn in the current diff, when it still has a place there.
    public var anchor: ReviewAnchor? {
        guard let line, !isFileLevel else { return nil }
        return ReviewAnchor(
            path: path, side: side, line: line, startLine: startLine, startSide: startSide)
    }

    private enum CodingKeys: String, CodingKey {
        case id, path, isResolved, isOutdated, line, startLine, originalLine, diffSide, startDiffSide,
            subjectType,
            viewerCanResolve, viewerCanUnresolve, viewerCanReply, resolvedBy, comments
    }

    private struct Login: Decodable {
        var login: String
    }

    private struct Comments: Decodable {
        var nodes: [ReviewComment]
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        path = try container.decode(String.self, forKey: .path)
        isResolved = try container.decodeIfPresent(Bool.self, forKey: .isResolved) ?? false
        isOutdated = try container.decodeIfPresent(Bool.self, forKey: .isOutdated) ?? false
        line = try container.decodeIfPresent(Int.self, forKey: .line)
        startLine = try container.decodeIfPresent(Int.self, forKey: .startLine)
        originalLine = try container.decodeIfPresent(Int.self, forKey: .originalLine)
        side = try container.decodeEnum(DiffSide.self, forKey: .diffSide) ?? .right
        startSide = try container.decodeEnum(DiffSide.self, forKey: .startDiffSide)
        isFileLevel = try container.decodeIfPresent(String.self, forKey: .subjectType) == "FILE"
        viewerCanResolve = try container.decodeIfPresent(Bool.self, forKey: .viewerCanResolve) ?? false
        viewerCanUnresolve =
            try container.decodeIfPresent(Bool.self, forKey: .viewerCanUnresolve) ?? false
        viewerCanReply = try container.decodeIfPresent(Bool.self, forKey: .viewerCanReply) ?? false
        resolvedBy = try container.decodeIfPresent(Login.self, forKey: .resolvedBy)?.login
        comments = try container.decodeIfPresent(Comments.self, forKey: .comments)?.nodes ?? []
    }
}
