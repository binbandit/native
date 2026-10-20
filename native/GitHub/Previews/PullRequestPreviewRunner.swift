#if NATIVE_PREVIEWS_WIP
import Exec
import Foundation
import GitHub

/// Answers the gh commands a pull request page runs with fixture JSON shaped like gh's, so page
/// previews load through the app's own code without gh, a network or a login. Anything else fails
/// as if gh weren't installed, so a preview never writes anywhere.
nonisolated struct PullRequestPreviewRunner: CommandRunner {
    enum Scenario: Sendable {
        /// Someone else's open pull request, under review: threads, a review, failing checks.
        case reviewing
        /// The viewer's own open pull request, ready to merge.
        case own
        /// A merged pull request.
        case merged
        /// gh can't reach GitHub.
        case offline
    }

    var scenario: Scenario = .reviewing

    static let reference = PullRequestReference(owner: "binbandit", name: "native", number: 212)

    func run(_ command: Command) async throws -> CommandResult {
        if scenario == .offline {
            return CommandResult(
                exitCode: 1, standardOutput: Data(),
                standardError: Data("error connecting to api.github.com\ncheck your internet connection".utf8))
        }
        let arguments = command.arguments
        let input = command.standardInput.map { String(decoding: $0, as: UTF8.self) } ?? ""
        let json: String? =
            if arguments.contains("graphql"), input.contains("mergeCommitAllowed") {
                PullRequestPagePreviewFixtures.page(scenario)
            } else if arguments.contains(where: { $0.contains("/pulls/212/files") }) {
                arguments.contains(where: { $0.hasSuffix("page=1") }) ? PullRequestPagePreviewFixtures.patches : "[]"
            } else if arguments.starts(with: ["pr", "checks"]) || arguments.contains("checks") {
                PullRequestPagePreviewFixtures.checks
            } else {
                nil
            }
        guard let json else { throw CommandError.notFound(command.executable) }
        return CommandResult(exitCode: 0, standardOutput: Data(json.utf8), standardError: Data())
    }
}
#endif
