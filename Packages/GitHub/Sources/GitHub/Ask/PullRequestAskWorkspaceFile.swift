import Foundation

/// A file saved in the folder a pull request question's agent works in, so it can read what didn't
/// fit in its context without asking GitHub.
public struct PullRequestAskWorkspaceFile: Sendable, Hashable {
    /// Relative to the folder, never leaving it.
    public var path: String
    public var contents: String

    public init(path: String, contents: String) {
        self.path = path
        self.contents = contents
    }

    /// A repository path made safe to write under the folder: no empty, `.` or `..` parts, so a
    /// path from GitHub can never point outside it. `nil` when nothing is left.
    public static func safePath(_ path: String) -> String? {
        let parts = path.split(separator: "/").filter { $0 != "." && $0 != ".." }
        return parts.isEmpty ? nil : parts.joined(separator: "/")
    }
}
