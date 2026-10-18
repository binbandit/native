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
            "Pull Requests", systemImage: "arrow.triangle.pull", isSelected: isSelected, shortcut: "⌘⇧P", action: showList
        ) {
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
