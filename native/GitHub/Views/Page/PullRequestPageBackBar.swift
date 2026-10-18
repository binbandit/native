import GitHub
import SwiftUI

/// Back to the list, and the pull request's reference, while its page hasn't loaded.
struct PullRequestPageBackBar: View {
    let reference: PullRequestReference

    @Environment(GitHubModel.self) private var gitHub

    var body: some View {
        HStack(spacing: DS.Space.md) {
            IconButton("Back to Pull Requests", systemImage: "chevron.left") { gitHub.closePullRequestPage() }
            Text(reference.display)
                .font(.dsBodyMedium)
                .foregroundStyle(.dsTextSecondary)
            Spacer(minLength: DS.Space.md)
            IconButton("Open on GitHub", systemImage: "arrow.up.right") { gitHub.openExternally(reference.url) }
        }
        .padding(.horizontal, DS.Space.lg)
        .frame(height: DS.Window.headerHeight + DS.Space.md)
    }
}
