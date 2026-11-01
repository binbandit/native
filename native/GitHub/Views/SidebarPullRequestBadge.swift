import GitHub
import SwiftUI

/// A task's outcome, kept quiet beside its title. Actions stay in the row's menu, so paired-host
/// pull requests cannot accidentally expose writes through this Mac's GitHub account.
struct SidebarPullRequestBadge: View {
    let pullRequest: PullRequestSummary

    var body: some View {
        HStack(spacing: DS.Space.xxs) {
            PullRequestStateIcon(
                state: pullRequest.state, isDraft: pullRequest.isDraft, size: DS.Size.navIcon, hasTooltip: false)
            Text("#\(pullRequest.number)")
                .font(DS.Sidebar.factFont)
                .foregroundStyle(.dsTextSecondary)
            if pullRequest.state == .open, let checks = pullRequest.checks, checks.state == .failing {
                ChecksIndicator(checks: checks, hasTooltip: false)
            }
        }
        .fixedSize()
        .help(pullRequest.spokenSummary)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(pullRequest.spokenSummary)
        .accessibilityIdentifier("sidebar-pr-\(pullRequest.number)")
    }
}

#if DEBUG
#Preview("Sidebar pull requests - Every outcome") {
    DSPreviewPair {
        VStack(alignment: .leading, spacing: DS.Space.md) {
            ForEach(SidebarPullRequestPreviewFixtures.pullRequests) { pullRequest in
                SidebarPullRequestBadge(pullRequest: pullRequest)
            }
        }
    }
}
#endif
