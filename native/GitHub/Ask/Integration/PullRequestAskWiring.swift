import Foundation
import GitHub

/// Connects private pull request questions to the app: the GitHub feature's entry points (the page
/// header's Ask, a row's "Ask About This PR…") open the panel, and search opens a conversation it
/// found on its pull request's page rather than as a task in the sidebar.
enum PullRequestAskWiring {
    static func connect(_ center: PullRequestAskCenter, app: AppModel, gitHub: GitHubModel) {
        center.connect(app: app, gitHub: gitHub)
        gitHub.askAboutPullRequest = { [weak center] reference in
            center?.ask(about: reference)
        }
        app.searchedSessionOpeners.append { [weak center] key, cwd in
            center?.openSearched(key, cwd: cwd) ?? false
        }
        // `-gitHubAskPullRequest <url>` opens a pull request's page with Ask open, for checks.
        if let link = UserDefaults.standard.string(forKey: "gitHubAskPullRequest"), let url = URL(string: link),
            let reference = PullRequestReference(url: url)
        {
            center.ask(about: reference)
        }
    }
}
