import GitHub
import SwiftUI

/// What the user can do with a pull request. Views call these rather than gh or the platform, so
/// other clients can drive the same actions.
extension GitHubModel {
    /// Opens the pull request where the user's setting says: its page in Native, or GitHub.
    func open(_ pullRequest: PullRequestSummary) {
        guard pullRequestOpening == .native, let reference = PullRequestReference(pullRequest) else {
            openInBrowser(pullRequest)
            return
        }
        open(reference)
    }

    /// Opens a pull request link where the user's setting says; other links go to the browser.
    func open(_ url: URL) {
        guard pullRequestOpening == .native, let reference = PullRequestReference(url: url) else {
            openExternally(url)
            return
        }
        open(reference, tab: PullRequestPageModel.Tab(url: url))
    }

    /// - Parameter tab: The tab to show, as GitHub links say with `/files` and `/checks`.
    func open(_ reference: PullRequestReference, tab: PullRequestPageModel.Tab? = nil) {
        if let tab { pageModel(for: reference).tab = tab }
        presentedPullRequest = reference
    }

    func closePullRequestPage() {
        presentedPullRequest = nil
    }

    /// The page's model, kept for the run so returning to a pull request shows it at once.
    func pageModel(for reference: PullRequestReference) -> PullRequestPageModel {
        if let page = pages[reference] { return page }
        let page = PullRequestPageModel(reference: reference, gitHub: self)
        pages[reference] = page
        return page
    }

    func openInBrowser(_ pullRequest: PullRequestSummary) {
        openExternally(pullRequest.url)
    }

    /// Opens the first failing check's log, so a red x leads straight to the failure; otherwise, or
    /// when gh can't say, the pull request's Checks tab.
    func openChecks(_ pullRequest: PullRequestSummary) async {
        let checksTab = pullRequest.url.appending(path: "checks")
        var destination = checksTab
        if pullRequest.checks?.state == .failing,
            let checks = try? await cli().checks(.number(pullRequest.number), in: location(of: pullRequest))
        {
            destination = checks.first { $0.outcome == .failed && $0.link != nil }?.link ?? checksTab
        }
        openExternally(destination)
    }

    /// Where gh finds a pull request's repository without a local checkout.
    func location(of pullRequest: PullRequestSummary) -> RepositoryLocation {
        let host = pullRequest.url.host() ?? "github.com"
        return .remote(host == "github.com" ? pullRequest.repository : "\(host)/\(pullRequest.repository)")
    }

    func copyURL(_ pullRequest: PullRequestSummary) {
        copy(pullRequest.url.absoluteString)
    }

    func copyBranch(_ pullRequest: PullRequestSummary) {
        if let branch = pullRequest.headRefName {
            copy(branch)
        }
    }

    func copy(_ text: String) {
        DSPasteboard.copy(text)
    }

    /// Asks the user to confirm before anything touches a working tree.
    func requestOpenAsTask(_ pullRequest: PullRequestSummary) {
        guard canOpenAsTask else { return }
        openAsTaskCandidate = pullRequest
    }

    // MARK: - Creating

    /// Shows the Create Pull Request sheet for a branch. This is the hook the Git feature's commit
    /// UI calls (through the app) once the branch is pushed.
    func presentCreatePullRequest(_ request: CreatePullRequestRequest) {
        createRequest = request
    }

    /// Opens a pull request from the already-pushed branch, then updates its badge and the inbox.
    func createPullRequest(_ pullRequest: NewPullRequest, in directory: URL) async throws(GitHubError) -> URL {
        let url = try await cli().createPullRequest(pullRequest, in: directory)
        invalidate(BranchReference(directory: directory, branch: pullRequest.head))
        Task { await refresh() }
        return url
    }

    /// The GitHub repository a checkout belongs to: its default branch is the base a new pull
    /// request merges into, and a failure says why one can't be opened (no gh, no login, no
    /// GitHub remote).
    func repository(of directory: URL) async throws(GitHubError) -> GitHubRepository {
        try await cli().repository(.directory(directory))
    }

    /// The open pull request a branch already has, so the sheet can point to it instead.
    func openPullRequest(for branch: BranchReference) async -> PullRequestSummary? {
        await loadPullRequest(for: branch, maxAge: 0)
        guard let pullRequest = pullRequest(for: branch), pullRequest.state == .open else { return nil }
        return pullRequest
    }
}
