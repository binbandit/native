import GitHub
import SwiftUI

/// Everything that can be done with a pull request from the list or a badge. Merging opens the same
/// confirmed sheet as the page; closing and reopening can be undone.
struct PullRequestActionsMenu: View {
    let pullRequest: PullRequestSummary
    /// Commenting, merging, closing and reopening: offered in the list, which shows their comment
    /// box, sheet, progress and undo.
    var offersListActions = false

    @Environment(GitHubModel.self) private var model

    var body: some View {
        if model.pullRequestOpening == .native {
            Button("Open", systemImage: "arrow.triangle.pull") {
                model.open(pullRequest)
            }
        }
        Button("Open on GitHub", systemImage: "arrow.up.right") {
            model.openInBrowser(pullRequest)
        }
        if let checks = pullRequest.checks {
            Button(checks.state == .failing ? "Open Failing Check" : "Open Checks", systemImage: "checklist") {
                Task { await model.openChecks(pullRequest) }
            }
        }
        if offersListActions {
            listActions
        }
        Divider()
        if model.canOpenAsTask, pullRequest.state == .open {
            Button("Open as Task…", systemImage: "arrow.down.to.line.compact") {
                model.requestOpenAsTask(pullRequest)
            }
        }
        if let ask = model.askAboutPullRequest, let reference = PullRequestReference(pullRequest) {
            Button("Ask About This PR…", systemImage: "questionmark.bubble") { ask(reference) }
        }
        Divider()
        Button("Copy URL", systemImage: "link") {
            model.copyURL(pullRequest)
        }
        if pullRequest.headRefName != nil {
            Button("Copy Branch Name", systemImage: "arrow.triangle.branch") {
                model.copyBranch(pullRequest)
            }
        }
    }

    @ViewBuilder private var listActions: some View {
        Divider()
        Button("Comment…", systemImage: "text.bubble") {
            model.commentingOn = pullRequest.url
        }
        if pullRequest.state == .open, !pullRequest.isDraft {
            Button("Merge…", systemImage: "arrow.triangle.merge") {
                model.requestMerge(pullRequest)
            }
        }
        if pullRequest.state == .open {
            Button("Close Pull Request", systemImage: "xmark.circle") {
                Task { await model.setOpen(false, pullRequest) }
            }
        } else if pullRequest.state == .closed {
            Button("Reopen Pull Request", systemImage: "arrow.uturn.backward.circle") {
                Task { await model.setOpen(true, pullRequest) }
            }
        }
    }
}
