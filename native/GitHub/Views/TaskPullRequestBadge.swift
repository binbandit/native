import GitHub
import SwiftUI

/// The pull request for a task's branch, at a task row's trailing edge: its state glyph, and its
/// checks while it's open. Clicking opens it (in Native or on GitHub, as Settings › GitHub says);
/// resting the pointer on it shows `TaskPullRequestCard`, which a tap shows on touch. The lookup
/// through gh is shared with every other badge on the same branch. Shows nothing while loading or
/// when the branch has none, so it can sit in a row unconditionally.
struct TaskPullRequestBadge: View {
    /// The task's checkout (its worktree).
    let directory: URL
    let branch: String

    @Environment(GitHubModel.self) private var model
    @State private var card = DSHoverCardState()
    @State private var isHovered = false

    var body: some View {
        let reference = BranchReference(directory: directory, branch: branch)
        // A real container, not a Group: modifiers on an empty Group apply to no views, so the
        // lookup would never start for a branch with nothing cached yet.
        ZStack {
            if let pullRequest = model.pullRequest(for: reference) {
                badge(pullRequest)
                    .dsHoverCard(card) {
                        TaskPullRequestCard(branch: reference, dismiss: card.dismiss)
                    }
            }
        }
        .task(id: reference) {
            await model.loadPullRequest(for: reference)
        }
    }

    private func badge(_ pullRequest: PullRequestSummary) -> some View {
        let checks = pullRequest.state == .open ? pullRequest.checks : nil
        return Button {
            if DS.isTouchPlatform {
                card.toggle()
            } else {
                card.dismiss()
                model.open(pullRequest)
            }
        } label: {
            HStack(spacing: DS.Space.xxs) {
                PullRequestStateIcon(
                    state: pullRequest.state, isDraft: pullRequest.isDraft, size: DS.Size.navIcon, hasTooltip: false)
                if let checks {
                    ChecksIndicator(checks: checks, hasTooltip: false)
                }
            }
            .padding(.horizontal, DS.Space.xxs)
            .frame(height: DS.Size.rowLeading)
            .background(
                isHovered || card.isPresented ? .dsHover : .clear,
                in: RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous)
            )
            .contentShape(.rect)
            .dsHitTarget(DS.Size.rowLeading)
        }
        .buttonStyle(.plain)
        .trackHover($isHovered)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(pullRequest.spokenSummary): \(pullRequest.title)")
        .accessibilityHint(DS.isTouchPlatform ? "Shows its details." : "Opens it.")
        .accessibilityAddTraits(.isButton)
        // Inside a row, these join the row's own actions, which already open and copy it.
        .accessibilityAction(named: "Show Pull Request Details") { card.toggle() }
    }
}

#if NATIVE_PREVIEWS_WIP
#Preview("Task pull request badge") {
    let pullRequests = Array(PullRequestPreviewFixtures.inbox.all.prefix(5))
    let folder = URL(filePath: "/Users/preview/Developer/native", directoryHint: .isDirectory)
    let branches = Dictionary(
        pullRequests.map { (BranchReference(directory: folder, branch: $0.headRefName ?? "\($0.number)"), $0) },
        uniquingKeysWith: { first, _ in first })
    DSPreviewPair {
        // Open with checks failing, running and passing, then a draft without checks.
        VStack(alignment: .leading, spacing: DS.Space.lg) {
            ForEach(pullRequests) { pullRequest in
                TaskPullRequestBadge(directory: folder, branch: pullRequest.headRefName ?? "\(pullRequest.number)")
            }
        }
    }
    .environment(GitHubModel.preview(inbox: PullRequestPreviewFixtures.inbox, branches: branches))
}
#endif
