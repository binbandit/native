import NativeCommands
import SwiftUI

/// The sidebar's "Pull Requests" item, with how many wait on the user's review.
struct PullRequestsNavItem: View {
    let isSelected: Bool
    let action: () -> Void

    @Environment(GitHubModel.self) private var model

    /// Back to the list from a pull request's page, as the other sidebar items lead to their top.
    private func showList() {
        model.closePullRequestPage()
        action()
    }

    var body: some View {
        SidebarNavItem(
            "Pull Requests", isSelected: isSelected,
            shortcut: CommandRegistry.shared.shortcut(for: .goPullRequests)?.displayString,
            action: showList
        ) {
            // SF Symbols' pull glyph draws a stunted hook at this size. The pull request mark reads,
            // drawn at the weight of the "+" above it (Lucide's 2-point stroke on a 24-point grid).
            PullRequestGlyph(kind: .open)
                .stroke(style: StrokeStyle(lineWidth: DS.Size.navIcon / 12, lineCap: .round, lineJoin: .round))
        } accessory: {
            if model.reviewRequestCount > 0 {
                Text("\(model.reviewRequestCount)")
                    .font(.dsMonoMicro)
                    .foregroundStyle(.dsTextSecondary)
                    .padding(.horizontal, DS.Space.xs)
                    .frame(minWidth: DS.Size.rowLeading, minHeight: DS.Size.statusGlyph)
                    .background(.dsSelected, in: .capsule)
                    .padding(.trailing, DS.Space.sm)
                    .help("\(model.reviewRequestCount) waiting on your review")
                    .accessibilityLabel("\(model.reviewRequestCount) waiting on your review")
            }
        }
    }
}

#if NATIVE_PREVIEWS_WIP
#Preview("Pull requests nav item") {
    DSPreviewPair {
        VStack(spacing: DS.Space.xxs) {
            PullRequestsNavItem(isSelected: false) {}
                .environment(GitHubModel.preview(inbox: PullRequestPreviewFixtures.inbox))
            PullRequestsNavItem(isSelected: true) {}
                .environment(GitHubModel.preview(inbox: PullRequestPreviewFixtures.inbox))
            // Nothing waiting on the user's review: no count.
            PullRequestsNavItem(isSelected: false) {}
                .environment(GitHubModel.preview())
        }
        .frame(width: DS.Size.sidebarWidth)
    }
}
#endif
