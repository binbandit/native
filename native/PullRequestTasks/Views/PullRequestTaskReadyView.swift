import GitHub
import SwiftUI

/// What opening the pull request will do, before it's done: the project it goes in, the branch it's
/// checked out on and where that pushes, the agent that starts, and whether the brief quotes the
/// reviews.
struct PullRequestTaskReadyView: View {
    let checkout: PullRequestTaskCheckout.ProjectCheckout
    /// The default agent's name; `nil` when none is installed.
    let agent: String?
    @Binding var includesReviewComments: Bool

    var body: some View {
        let details = checkout.details
        VStack(alignment: .leading, spacing: DS.Space.lg) {
            HStack(spacing: DS.Space.xs) {
                BranchChip(name: headLabel)
                Image(systemName: "arrow.right")
                    .font(.dsCaption)
                    .foregroundStyle(.dsTextTertiary)
                    .accessibilityLabel("into")
                BranchChip(name: details.baseRefName)
            }
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: DS.Space.lg, verticalSpacing: DS.Space.md) {
                fact("Project") {
                    Text(checkout.project.name)
                        .foregroundStyle(.dsTextPrimary)
                    Text(PullRequestTaskPaths.abbreviated(checkout.project.url))
                        .font(.dsCaption)
                        .foregroundStyle(.dsTextTertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                fact("Branch") {
                    Text(checkout.reusableFolder?.lastPathComponent ?? checkout.plan.branch)
                        .font(.dsMonoCaption)
                        .foregroundStyle(.dsTextPrimary)
                        .textSelection(.enabled)
                    Text(branchNote)
                        .font(.dsCaption)
                        .foregroundStyle(.dsTextSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                fact("Agent") {
                    Text(agent ?? "No agent is installed yet; Native asks you to add one.")
                        .foregroundStyle(agent == nil ? .dsTextSecondary : .dsTextPrimary)
                }
            }
            .font(.dsBody)
            GitHubCheckbox(
                title: "Include reviews and open review comments in the task's brief", isOn: $includesReviewComments)
            Text(footnote)
                .font(.dsCaption)
                .foregroundStyle(.dsTextTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(DS.Space.xl)
    }

    private var footnote: String {
        let place =
            checkout.reusableFolder == nil
            ? "It's checked out in a new worktree" : "It opens in its existing worktree"
        return place
            + ", so the project's own checkout isn't touched. The task's first message carries a brief on the pull request: its description, its link and how to push."
    }

    private func fact(_ label: String, @ViewBuilder value: () -> some View) -> some View {
        GridRow {
            Text(label)
                .foregroundStyle(.dsTextTertiary)
                .frame(width: PullRequestTaskSheetLayout.labelWidth, alignment: .leading)
            VStack(alignment: .leading, spacing: DS.Space.xxs) {
                value()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// The head as GitHub writes it: `owner:branch` when it's in a fork.
    private var headLabel: String {
        let details = checkout.details
        guard details.isCrossRepository else { return details.headRefName }
        return "\(details.headRepository?.owner ?? "deleted fork"):\(details.headRefName)"
    }

    private var branchNote: String {
        if let folder = checkout.reusableFolder {
            return "The worktree made for it earlier (\(folder.lastPathComponent)), which no task is using."
        }
        let details = checkout.details
        switch checkout.plan.source {
        case .remote(let remote, let branch):
            return "Tracks \(remote)/\(branch), so pushes update the pull request."
        case .newRemote(let remote, _, let branch):
            return
                "Tracks \(branch) in \(remote)'s fork, added as the remote “\(remote)”, so pushes update the pull request."
        case .pullRef:
            guard let fork = details.headRepository, details.isCrossRepository else {
                return
                    "From GitHub's copy of the pull request. The fork it came from is gone, so pushes can't update it."
            }
            return
                "From GitHub's copy of the pull request. Your account can't push to \(fork.owner)'s fork, so pushes can't update it."
        }
    }
}

enum PullRequestTaskPaths {
    /// `~/Developer/slugify` rather than the whole home folder's path.
    static func abbreviated(_ url: URL) -> String {
        let path = url.folderPath
        let home = URL.homeDirectory.folderPath
        return path == home || path.hasPrefix(home + "/") ? "~" + path.dropFirst(home.count) : path
    }
}
