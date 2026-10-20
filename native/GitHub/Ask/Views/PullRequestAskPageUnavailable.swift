import GitHub
import SwiftUI

/// The panel while gh can't read the pull request: questions need its context, so this says why
/// it's missing and offers the fix. The page beside it shows the same problem in full.
struct PullRequestAskPageUnavailable: View {
    let page: PullRequestPageModel
    let error: GitHubError

    @Environment(GitHubModel.self) private var gitHub

    var body: some View {
        EmptyStateView(title, systemImage: systemImage, message: message) {
            VStack(spacing: DS.Space.lg) {
                if let command {
                    CommandSnippet(command: command) { gitHub.copy(command) }
                }
                Button(page.isLoading ? "Checking…" : "Try Again") {
                    Task {
                        // A gh installed or signed in since launch needs the environment read again.
                        await gitHub.refresh(rereadEnvironment: true)
                        await page.load()
                    }
                }
                .buttonStyle(.ds(.primary, size: .medium))
                .disabled(page.isLoading)
            }
        }
    }

    private var title: String {
        switch error {
        case .notInstalled: "Questions need GitHub CLI"
        case .notAuthenticated: "Sign in to GitHub CLI to ask"
        case .offline, .timedOut: "GitHub can't be reached"
        case .rateLimited: "GitHub's rate limit was reached"
        case .notFound: "This pull request can't be found"
        default: "This pull request didn't load"
        }
    }

    private var systemImage: String {
        switch error {
        case .notInstalled: "terminal"
        case .notAuthenticated: "person.badge.key"
        case .offline, .timedOut: "wifi.slash"
        default: "exclamationmark.triangle"
        }
    }

    private var message: String {
        switch error {
        case .notInstalled:
            "Native reads the pull request through gh to give the agent its context. Install it, then try again."
        case .notAuthenticated:
            "Native reads the pull request through gh, which isn't signed in. Sign in in a terminal, then try again."
        case .offline, .timedOut:
            "Questions start once the pull request loads. Native tries again when the network is back."
        case .rateLimited:
            "Questions start once the pull request loads, when GitHub lets gh ask again."
        case .notFound:
            "It may have been deleted, or the account gh is signed in to can't see it. Questions need it to load first."
        default:
            "Questions need it to load first. " + error.localizedDescription
        }
    }

    private var command: String? {
        switch error {
        case .notInstalled: "brew install gh"
        case .notAuthenticated:
            "gh auth login" + (page.reference.host == "github.com" ? "" : " --hostname \(page.reference.host)")
        default: nil
        }
    }
}

#if NATIVE_PREVIEWS_WIP
#Preview("Ask - Pull request unavailable") {
    let gitHub = GitHubModel.preview()
    let page = PullRequestPageModel(reference: PullRequestPreviewRunner.reference, gitHub: gitHub)
    DSPreviewPair {
        VStack(spacing: DS.Space.xl) {
            PullRequestAskPageUnavailable(page: page, error: .offline("error connecting to api.github.com"))
            PullRequestAskPageUnavailable(page: page, error: .notAuthenticated(""))
            PullRequestAskPageUnavailable(page: page, error: .notFound("Could not resolve to a PullRequest"))
        }
        .frame(width: PullRequestAskMetrics.panelIdealWidth)
    }
    .environment(gitHub)
}
#endif
