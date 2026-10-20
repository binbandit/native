import GitHub
import SwiftUI

/// Why the list can't show anything yet, what Native is doing about it, and the one thing to do
/// next. Native never installs gh or signs in for the user: it shows the command, then checks again
/// without a restart.
struct GitHubSetupView: View {
    enum Problem {
        case notInstalled
        case notAuthenticated
        case failed(GitHubError)
    }

    let problem: Problem
    /// What "Check Again" does; refreshing the pull request list unless given.
    var retry: (() async -> Void)?

    @Environment(GitHubModel.self) private var model

    var body: some View {
        EmptyStateView(title, systemImage: systemImage, message: message) {
            VStack(spacing: DS.Space.lg) {
                if let command {
                    CommandSnippet(command: command) { model.copy(command) }
                }
                if let action = primaryAction {
                    Button(model.isRefreshing ? "Checking…" : action) {
                        Task {
                            if let retry { await retry() } else { await model.refresh(rereadEnvironment: true) }
                        }
                    }
                    .buttonStyle(.ds(.primary, size: .medium))
                    .disabled(model.isRefreshing)
                }
                if case .notInstalled = problem {
                    Button("Other ways to install at cli.github.com") {
                        if let url = URL(string: "https://cli.github.com") { model.openExternally(url) }
                    }
                    .buttonStyle(.ds(.ghost))
                }
            }
        }
    }

    private var title: String {
        switch problem {
        case .notInstalled: "Install GitHub CLI"
        case .notAuthenticated: "Sign In to GitHub CLI"
        case .failed(.offline): "GitHub Can't Be Reached"
        case .failed(.rateLimited): "GitHub's Rate Limit Was Reached"
        case .failed(.notARepository): "Not a GitHub Repository"
        case .failed: "Pull Requests Couldn't Load"
        }
    }

    private var systemImage: String {
        switch problem {
        case .notInstalled: "terminal"
        case .notAuthenticated: "person.badge.key"
        case .failed(.offline): "wifi.slash"
        case .failed(.rateLimited): "hourglass"
        case .failed(.notARepository): "folder.badge.questionmark"
        case .failed: "exclamationmark.triangle"
        }
    }

    private var message: String {
        switch problem {
        case .notInstalled:
            "Pull requests come from gh, GitHub's command-line tool, so your login, hosts and GitHub Enterprise just work. Native couldn't find it on your PATH. Install it in a terminal, then check again."
        case .notAuthenticated:
            "gh is installed but isn't signed in. Run this in a terminal and follow the prompts; Native uses whichever account gh is signed in to."
        case .failed(.offline):
            "Native couldn't connect to GitHub. It tries again on its own as soon as you're back online."
        case .failed(.rateLimited):
            "GitHub limits how often your account can search. Native waits and refreshes on its own \(Self.whenText(model.schedule.nextRefresh(.watching)))."
        case .failed(.notARepository(let detail)):
            detail.localizedCaseInsensitiveContains("not a git repository")
                ? "This folder isn't a git repository yet, so it has no branch to open a pull request from."
                : "None of this folder's git remotes point to GitHub. Add one (git remote add origin …), then check again."
        case .failed(let error):
            "\(error.stderr.flatMap { $0.isEmpty ? nil : $0 } ?? error.localizedDescription) Native tries again \(Self.whenText(model.schedule.nextRefresh(.watching)))."
        }
    }

    private var command: String? {
        switch problem {
        case .notInstalled: "brew install gh"
        case .notAuthenticated: "gh auth login"
        case .failed: nil
        }
    }

    /// Rate limits can't be hurried, so they offer nothing to press.
    private var primaryAction: String? {
        switch problem {
        case .notInstalled, .notAuthenticated: "Check Again"
        case .failed(.rateLimited): nil
        case .failed(.notARepository): "Check Again"
        case .failed: "Try Now"
        }
    }

    /// "at 3:05 PM, in 42 min": the exact time and how long that is.
    static func whenText(_ date: Date) -> String {
        guard date > .now.addingTimeInterval(30) else { return "shortly" }
        return "at \(DSFormat.timeAndCountdown(date, now: .now))"
    }
}

#if NATIVE_PREVIEWS_WIP
#Preview("GitHub setup") {
    DSPreviewPair {
        VStack(spacing: DS.Space.xxl) {
            GitHubSetupView(problem: .notInstalled)
            GitHubSetupView(problem: .notAuthenticated)
            GitHubSetupView(problem: .failed(.offline("error connecting to api.github.com")))
        }
        .frame(width: 560)
    }
    .environment(GitHubModel.preview(availability: .notInstalled, error: .notInstalled))
}
#endif
