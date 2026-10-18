import GitHub
import SwiftUI

/// Why a pull request's page couldn't open, and the way forward: the same designed states as the
/// list for gh missing or signed out, and GitHub's reason otherwise.
struct PullRequestPageLoadError: View {
    let model: PullRequestPageModel
    let error: GitHubError

    @Environment(GitHubModel.self) private var gitHub

    var body: some View {
        switch error {
        case .notInstalled:
            GitHubSetupView(problem: .notInstalled) { await model.load() }
        case .notAuthenticated:
            GitHubSetupView(problem: .notAuthenticated) { await model.load() }
        case .notFound:
            ErrorState(
                "\(model.reference.display) couldn't be found",
                suggestion: "It may have been deleted, or the account gh is signed in to can't see the repository.",
                primary: .init("Open on GitHub") { gitHub.openExternally(model.reference.url) },
                secondary: .init("Back to Pull Requests") { gitHub.closePullRequestPage() },
                layout: .pane)
        case .rateLimited, .offline, .timedOut:
            GitHubSetupView(problem: .failed(error)) { await model.load() }
        default:
            ErrorState(
                "The pull request couldn't load",
                suggestion: "Try again, or open it on GitHub.",
                details: error.stderr,
                primary: .init("Try Again") { Task { await model.load() } },
                secondary: .init("Open on GitHub") { gitHub.openExternally(model.reference.url) },
                layout: .pane)
        }
    }
}
