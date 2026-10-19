#if DEBUG
import Exec
import Foundation

/// Answers Clean Up Merged's GitHub questions from a file instead of asking GitHub, so squash merges
/// can be checked against a scratch repository with no GitHub remote. Debug builds only, with
/// `-gitCleanupFakePullRequests <path>`: a JSON object from local branch name to the pull request
/// that merged it, `{"fix-login": {"number": 123, "headRefOid": "<sha>", "baseRefName": "main"}}`.
/// Everything else goes to gh.
final class GitCleanupFakeGitHubRunner: CommandRunner {
    static let fileKey = "gitCleanupFakePullRequests"

    private struct Merged: Decodable {
        let number: Int
        let headRefOid: String
        let baseRefName: String?
    }

    private let base: any CommandRunner
    private let path: String

    /// `base` alone, unless the launch argument names a file.
    static func wrapping(_ base: any CommandRunner) -> any CommandRunner {
        guard let path = UserDefaults.standard.string(forKey: fileKey), !path.isEmpty else { return base }
        return GitCleanupFakeGitHubRunner(base: base, path: path)
    }

    private init(base: any CommandRunner, path: String) {
        self.base = base
        self.path = path
    }

    func run(_ command: Command) async throws -> CommandResult {
        let arguments = command.arguments
        if arguments.prefix(2) == ["repo", "view"] {
            return Self.success(
                #"{"name":"scratch","nameWithOwner":"native-dev/scratch","url":"https://github.com/native-dev/scratch"}"#
            )
        }
        guard arguments.prefix(2) == ["api", "graphql"], let input = command.standardInput,
            let request = try? JSONSerialization.jsonObject(with: input) as? [String: Any],
            let query = request["query"] as? String, query.contains("query MergedCleanup"),
            let variables = request["variables"] as? [String: Any]
        else { return try await base.run(command) }
        let merged =
            (try? JSONDecoder().decode([String: Merged].self, from: Data(contentsOf: URL(filePath: path)))) ?? [:]
        var repository: [String: Any] = [:]
        for (alias, value) in variables where alias.hasPrefix("h") {
            guard let head = value as? String else { continue }
            let nodes = merged[head].map { pullRequest in
                [
                    [
                        "number": pullRequest.number,
                        "url": "https://github.com/native-dev/scratch/pull/\(pullRequest.number)",
                        "headRefName": head, "headRefOid": pullRequest.headRefOid,
                        "baseRefName": pullRequest.baseRefName ?? "main", "mergedAt": "2026-10-19T09:00:00Z",
                    ] as [String: Any]
                ]
            }
            repository[alias] = ["nodes": nodes ?? []]
        }
        let response = try JSONSerialization.data(withJSONObject: ["data": ["repository": repository]])
        return CommandResult(exitCode: 0, standardOutput: response, standardError: Data())
    }

    private static func success(_ json: String) -> CommandResult {
        CommandResult(exitCode: 0, standardOutput: Data(json.utf8), standardError: Data())
    }
}
#endif
