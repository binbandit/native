import Foundation

/// Where a pull request's private conversation runs, under the app's `PullRequestQuestions`
/// folder: `<host>/<owner>/<name>-<number>`. Named so that what shows a session's folder (search,
/// Usage) reads as the pull request, and read back so a conversation found by its folder alone
/// (search, after its record was replaced) still opens on its pull request.
public enum PullRequestAskFolder {
    /// The folder every conversation lives under.
    public static let root = "PullRequestQuestions"

    /// The conversation's folder, relative to `root`.
    public static func relativePath(for reference: PullRequestReference) -> String {
        "\(reference.host)/\(reference.owner)/\(reference.name)-\(reference.number)"
    }

    /// The pull request a folder belongs to, from a full path that runs through `root`, or nil for
    /// any other folder.
    public static func reference(inPath path: String) -> PullRequestReference? {
        let parts = path.split(separator: "/").map(String.init)
        guard let start = parts.lastIndex(of: root), parts.count == start + 4 else { return nil }
        let leaf = parts[start + 3]
        guard let dash = leaf.lastIndex(of: "-"), let number = Int(leaf[leaf.index(after: dash)...]),
            dash != leaf.startIndex
        else { return nil }
        return PullRequestReference(
            host: parts[start + 1], owner: parts[start + 2], name: String(leaf[..<dash]), number: number)
    }
}
