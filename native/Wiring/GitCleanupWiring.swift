import Foundation
import Git
import GitHub

/// Gives Clean Up Merged (Git feature) what it needs from the rest of the app: the tasks, the
/// branch prefix (which can be the GitHub username) and GitHub's merged pull requests, which find
/// squash and rebase merges git's history can't show.
enum GitCleanupWiring {
    static func center(app: AppModel, git: GitStore, gitHub: GitHubModel) -> GitCleanupCenter {
        GitCleanupCenter(
            services: GitCleanupServices(
                app: app, git: git,
                branchPrefix: { [weak gitHub] project in
                    var login = gitHub?.currentLogin
                    if login == nil, git.settings.branchPrefixMode == .gitHubUsername {
                        login = try? await gitHub?.cli().currentUser().login
                    }
                    return git.settings.branchPrefix(forProjectAt: project, gitHubLogin: login)
                },
                pullRequests: { [weak gitHub] queries, project in
                    guard let gitHub else { return .unavailable("GitHub isn't set up") }
                    return await mergedPullRequests(queries, in: project, cli: await gitHub.cli())
                }))
    }

    private static func mergedPullRequests(
        _ queries: [CleanupPullRequestLookup.Query], in project: URL, cli: GitHubCLI
    ) async -> CleanupPullRequestLookup {
        var cli = cli
        #if DEBUG
        cli = GitHubCLI(
            environment: cli.environment, host: cli.host, runner: GitCleanupFakeGitHubRunner.wrapping(cli.runner))
        #endif
        do {
            let found = try await cli.mergedPullRequests(
                for: queries.map {
                    MergedPullRequest.Query(branch: $0.branch, head: $0.head, pullRequest: $0.linkedPullRequest)
                },
                in: project)
            return .found(
                found.mapValues { pullRequests in
                    pullRequests.map {
                        .init(number: $0.number, url: $0.url, headCommit: $0.headRefOid, base: $0.baseRefName)
                    }
                })
        } catch {
            return .unavailable(reason(error))
        }
    }

    /// Why GitHub couldn't be asked, as the end of "GitHub couldn't be asked (…)".
    private static func reason(_ error: GitHubError) -> String {
        switch error {
        case .notInstalled: "gh isn't installed"
        case .notAuthenticated: "gh isn't signed in"
        case .offline, .timedOut: "it couldn't be reached"
        case .notARepository: "the project has no GitHub remote"
        case .rateLimited: "its rate limit was reached"
        case .notFound, .permissionDenied: "the repository isn't visible to your account"
        case .cancelled, .failed, .unexpectedOutput: "it didn't answer"
        }
    }
}
