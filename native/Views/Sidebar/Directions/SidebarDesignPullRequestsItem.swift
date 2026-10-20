#if DEBUG
import NativeCommands
import SwiftUI

/// "Pull Requests" for the directions that keep it as a row: today's item, counting the fixture's
/// reviews too (`SidebarDesignFixture.reviewRequests`).
struct SidebarDesignPullRequestsItem: View {
    @Environment(GitHubModel.self) private var gitHub
    let destinations: SidebarDesignDestinations

    var body: some View {
        let count = SidebarDesignFixture.reviewRequests(gitHub)
        SidebarNavItem(
            "Pull Requests", systemImage: "arrow.triangle.pull", isSelected: destinations.isShowingPullRequests,
            shortcut: CommandRegistry.shared.shortcut(for: .goPullRequests)?.displayString
        ) {
            gitHub.closePullRequestPage()
            destinations.showPullRequests()
        } accessory: {
            if count > 0 {
                Text("\(count)")
                    .font(.dsMonoMicro)
                    .foregroundStyle(.dsTextSecondary)
                    .padding(.horizontal, DS.Space.xs)
                    .frame(minWidth: DS.Size.rowLeading, minHeight: DS.Size.statusGlyph)
                    .background(.dsSelected, in: .capsule)
                    .padding(.trailing, DS.Space.sm)
                    .help("\(count) waiting on your review")
            }
        }
    }
}
#endif
