import GitHub
import SwiftUI

/// Everything that can be done with a pull request from the list or a badge. Merging isn't here: it
/// belongs to a deliberate, confirmed action in a task, not a context menu.
struct PullRequestActionsMenu: View {
    let pullRequest: PullRequestSummary

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
        if model.canOpenAsTask, pullRequest.state == .open {
            Button("Open as Task…", systemImage: "arrow.down.to.line.compact") {
                model.requestOpenAsTask(pullRequest)
            }
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
}
