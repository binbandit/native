#if DEBUG
import ACP
import Exec
import Foundation
import Git
import GitHub

/// Git and gh wire-shaped answers for the real row lookup. Existing source folders stand in for
/// checkouts, so previews need no file writes, subprocesses, credentials or network.
nonisolated struct SidebarPullRequestFixtureRunner: CommandRunner {
    func run(_ command: Command) async throws -> CommandResult {
        let folder = command.directory ?? "/fixture/sidebar"
        let index = await MainActor.run {
            SidebarPullRequestPreviewFixtures.checkouts.firstIndex { SessionFolder.isSame($0.path, folder) }
        }
        let output: String
        if command.executable == "git" {
            switch command.arguments.first {
            case "rev-parse": output = "\(folder)\n\(folder)/.git\n\(folder)/.git\n"
            case "status": output = "# branch.oid abc123\0# branch.head task/\(index ?? 0)\0"
            case "remote": output = "origin\n"
            default: output = ""
            }
        } else if command.arguments.first == "auth" {
            output =
                #"{"hosts":{"github.com":[{"state":"success","active":true,"host":"github.com","login":"fixture"}]}}"#
        } else if command.arguments.first == "api" {
            output = #"{"login":"fixture"}"#
        } else if let index {
            let pr = await MainActor.run { SidebarPullRequestPreviewFixtures.pullRequests[index] }
            let checks =
                pr.checks?.state == .failing
                ? #"[{"__typename":"CheckRun","name":"Tests","status":"COMPLETED","conclusion":"FAILURE"}]"# : "[]"
            output = """
                [{"number":\(pr.number),"title":"\(pr.title)","url":"https://github.com/fixture/sidebar/pull/\(pr.number)",\
                "state":"\(pr.state.rawValue)","isDraft":\(pr.isDraft),"headRefName":"task/\(index)","baseRefName":"main",\
                "createdAt":"2026-10-01T00:00:00Z","updatedAt":"2026-10-01T00:00:00Z","statusCheckRollup":\(checks)}]
                """
        } else {
            output = "[]"
        }
        return CommandResult(exitCode: 0, standardOutput: Data(output.utf8), standardError: Data())
    }
}

nonisolated struct SidebarPullRequestFixtureMonitor: RepositoryMonitor {
    func changes(in repository: Repository) -> AsyncStream<RepositoryChange> { AsyncStream { $0.finish() } }
}
#endif
