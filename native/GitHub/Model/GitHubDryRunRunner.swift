#if DEBUG
import Exec
import Foundation

/// Runs gh for real but answers the writes the pull request list and page make (merge, close,
/// reopen, comment, and the page's GraphQL mutations) without sending them, so their flows can be
/// checked end to end against real pull requests. Debug builds only, with `-gitHubDryRunWrites YES`;
/// `-gitHubDryRunFails YES` makes those writes fail instead, and `-gitHubDryRunLog <path>` records
/// each one.
///
/// `-gitHubFakeMergeRoute <route>` also shows every pull request as merging one way, to check each
/// merge control against real data: `queue`, `queued`, `removed` (from the queue), `auto`,
/// `autoOn`, `direct` (green) or `blocked`; add `+admin` for an admin's view.
///
/// `gitHubDryRunOffline` and `gitHubDryRunSignedOut` make every read fail as gh does offline or
/// signed out. They're read on each command, so `defaults write <bundle id> gitHubDryRunOffline
/// -bool YES` while the app runs turns what already loaded stale, as a dropped network would.
final class GitHubDryRunRunner: CommandRunner {
    static let enabledKey = "gitHubDryRunWrites"

    private let base: any CommandRunner

    init(base: any CommandRunner) {
        self.base = base
    }

    func run(_ command: Command) async throws -> CommandResult {
        guard Self.isWrite(command) else {
            let defaults = UserDefaults.standard
            if defaults.bool(forKey: "gitHubDryRunOffline") {
                return CommandResult(
                    exitCode: 1, standardOutput: Data(),
                    standardError: Data("error connecting to api.github.com\ncheck your internet connection".utf8))
            }
            if defaults.bool(forKey: "gitHubDryRunSignedOut") {
                return CommandResult(
                    exitCode: 4, standardOutput: Data(),
                    standardError: Data("To get started with GitHub CLI, please run:  gh auth login".utf8))
            }
            let result = try await base.run(command)
            guard let route = UserDefaults.standard.string(forKey: "gitHubFakeMergeRoute"), !route.isEmpty else {
                return result
            }
            return Self.faking(route, in: result, for: command)
        }
        let defaults = UserDefaults.standard
        if let path = defaults.string(forKey: "gitHubDryRunLog"), !path.isEmpty {
            var described = command.arguments.joined(separator: " ")
            // A GraphQL write says which mutation it is.
            if let input = command.standardInput,
                let match = String(decoding: input, as: UTF8.self).firstMatch(of: /mutation\(\$input: (\w+)Input/)
            {
                described += " " + match.1
            }
            let line = Data((described + "\n").utf8)
            if let handle = FileHandle(forWritingAtPath: path) {
                handle.seekToEndOfFile()
                handle.write(line)
                handle.closeFile()
            } else {
                FileManager.default.createFile(atPath: path, contents: line)
            }
        }
        // Long enough to see the progress state.
        try? await Task.sleep(for: .seconds(1))
        if defaults.bool(forKey: "gitHubDryRunFails") {
            return CommandResult(
                exitCode: 1, standardOutput: Data(),
                standardError: Data("GraphQL: Resource not accessible by integration (dry run)".utf8))
        }
        return CommandResult(exitCode: 0, standardOutput: Data(), standardError: Data())
    }

    /// The page's or the list's status query, rewritten to merge the given way.
    private static func faking(_ route: String, in result: CommandResult, for command: Command) -> CommandResult {
        guard command.arguments.first == "api", let input = command.standardInput,
            String(decoding: input, as: UTF8.self).contains("mergeQueueEntry"),
            var json = (try? JSONSerialization.jsonObject(with: result.standardOutput)) as? [String: Any],
            var data = json["data"] as? [String: Any]
        else { return result }
        if var repository = data["repository"] as? [String: Any],
            var pullRequest = repository["pullRequest"] as? [String: Any]
        {
            fake(route, &repository, &pullRequest)
            repository["pullRequest"] = pullRequest
            data["repository"] = repository
        } else if let nodes = data["nodes"] as? [[String: Any]] {
            data["nodes"] = nodes.map { node in
                var repository: [String: Any] = [:]
                var pullRequest = node
                fake(route, &repository, &pullRequest)
                return pullRequest
            }
        }
        json["data"] = data
        guard let output = try? JSONSerialization.data(withJSONObject: json) else { return result }
        return CommandResult(exitCode: result.exitCode, standardOutput: output, standardError: result.standardError)
    }

    private static func fake(_ route: String, _ repository: inout [String: Any], _ pullRequest: inout [String: Any]) {
        let parts = route.split(separator: "+")
        repository["viewerPermission"] = "WRITE"
        pullRequest["viewerCanMergeAsAdmin"] = parts.contains("admin")
        pullRequest["mergeable"] = "MERGEABLE"
        pullRequest["mergeQueueEntry"] = NSNull()
        pullRequest["autoMergeRequest"] = NSNull()
        switch parts.first {
        case "queue", "queued", "removed":
            pullRequest["isMergeQueueEnabled"] = true
            pullRequest["mergeStateStatus"] = "BLOCKED"
            if parts.first == "queued" { pullRequest["mergeQueueEntry"] = ["position": 3, "state": "AWAITING_CHECKS"] }
            if parts.first == "removed" {
                pullRequest["queueEvents"] = [
                    "nodes": [["__typename": "RemovedFromMergeQueueEvent", "reason": "failed checks"]]
                ]
            }
        case "auto", "autoOn":
            pullRequest["isMergeQueueEnabled"] = false
            repository["autoMergeAllowed"] = true
            pullRequest["mergeStateStatus"] = "BLOCKED"
            pullRequest["viewerCanEnableAutoMerge"] = true
            pullRequest["viewerCanDisableAutoMerge"] = true
            if parts.first == "autoOn" { pullRequest["autoMergeRequest"] = ["mergeMethod": "SQUASH"] }
        default:
            pullRequest["isMergeQueueEnabled"] = false
            repository["autoMergeAllowed"] = false
            pullRequest["mergeStateStatus"] = parts.first == "blocked" ? "BLOCKED" : "CLEAN"
        }
    }

    private static func isWrite(_ command: Command) -> Bool {
        let arguments = command.arguments
        if arguments.first == "pr" {
            return ["merge", "close", "reopen", "comment"].contains(arguments.dropFirst().first)
        }
        // GraphQL requests go through stdin; a mutation says so before its first brace.
        guard arguments.first == "api", let input = command.standardInput else { return false }
        return String(decoding: input, as: UTF8.self).contains("mutation")
    }
}
#endif
