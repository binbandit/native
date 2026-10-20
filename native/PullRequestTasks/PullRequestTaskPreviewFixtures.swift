#if NATIVE_PREVIEWS_WIP
import Foundation
import GitHub

/// Open as Task previews' data: a pull request as gh describes it, in a project, and with none.
enum PullRequestTaskPreviewFixtures {
    static let reference = PullRequestReference(owner: "binbandit", name: "native", number: 212)

    static let details = PullRequestDetails(
        number: 212, title: "Queue follow-ups while a turn runs",
        body: "Messages sent while the agent works wait above the composer and go when the turn ends.",
        url: URL(string: "https://github.com/binbandit/native/pull/212") ?? URL(filePath: "/"),
        author: "preview-author", baseRefName: "main", headRefName: "native/queue-follow-ups",
        headRefOid: "4f2c9e1a7b3d", headRepository: RemoteRepository(owner: "binbandit", name: "native"),
        isCrossRepository: false,
        reviews: [
            PullRequestDetails.Review(
                author: "preview-reviewer", state: .changesRequested,
                body: "The queue should survive a relaunch.")
        ])

    static func checkout(in app: AppModel) -> PullRequestTaskCheckout.ProjectCheckout? {
        guard let project = app.previewProject() else { return nil }
        return PullRequestTaskCheckout.ProjectCheckout(
            project: project, details: details,
            plan: PullRequestCheckoutPlan(
                source: .remote(name: "origin", branch: "native/queue-follow-ups"), branch: "pr-212-queue-follow-ups"),
            reusableFolder: nil)
    }

    static let noProject = PullRequestTaskCheckout.NoProject(
        details: details, repository: RemoteRepository(owner: "binbandit", name: "native"))

    static let offline = PullRequestTaskProblem(
        GitHubError.offline("error connecting to api.github.com"), during: .lookingUp(reference))

    /// An opener that never asks GitHub or git anything until someone acts in the sheet.
    static func opener(_ app: AppModel) -> PullRequestTaskOpener {
        PullRequestTaskOpener(
            checkout: PullRequestTaskCheckout(
                app: app, git: GitStore(environment: { [:] }, settings: GitSettings(defaults: PreviewUserDefaults())),
                gitHub: GitHubModel.preview(inbox: PullRequestPreviewFixtures.inbox)),
            defaults: PreviewUserDefaults())
    }
}
#endif
