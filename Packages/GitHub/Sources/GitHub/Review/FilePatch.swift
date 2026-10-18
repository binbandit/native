import Foundation

/// A changed file with its diff, from REST's `pulls/{number}/files`, the only API that returns
/// patches. GitHub leaves `patch` out for binary files and diffs too large to show.
public struct FilePatch: Sendable, Hashable, Decodable {
    public var path: String
    /// The path before a rename.
    public var previousPath: String?
    /// `added`, `removed`, `modified`, `renamed`, ...
    public var status: String
    public var additions: Int
    public var deletions: Int
    public var patch: String?

    public init(
        path: String, previousPath: String? = nil, status: String, additions: Int, deletions: Int,
        patch: String?
    ) {
        self.path = path
        self.previousPath = previousPath
        self.status = status
        self.additions = additions
        self.deletions = deletions
        self.patch = patch
    }

    /// The parsed hunks; empty when GitHub sent no patch.
    public var hunks: [DiffHunk] {
        patch.map(DiffHunk.parse) ?? []
    }

    /// Why there's no diff to show, when there isn't one.
    public var missingPatchReason: MissingPatchReason? {
        guard patch == nil else { return nil }
        if status == "renamed", additions == 0, deletions == 0 { return .renamedOnly }
        return additions == 0 && deletions == 0 ? .binary : .tooLarge
    }

    public enum MissingPatchReason: Sendable, Hashable {
        case binary
        case tooLarge
        case renamedOnly
    }

    private enum CodingKeys: String, CodingKey {
        case filename
        case previousFilename = "previous_filename"
        case status, additions, deletions, patch
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        path = try container.decode(String.self, forKey: .filename)
        previousPath = try container.decodeText(forKey: .previousFilename)
        status = try container.decodeIfPresent(String.self, forKey: .status) ?? "modified"
        additions = try container.decodeIfPresent(Int.self, forKey: .additions) ?? 0
        deletions = try container.decodeIfPresent(Int.self, forKey: .deletions) ?? 0
        patch = try container.decodeText(forKey: .patch)
    }
}
