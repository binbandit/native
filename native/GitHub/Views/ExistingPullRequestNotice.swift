import GitHub
import SwiftUI

/// When the branch already has an open pull request, a way to it instead of a duplicate.
struct ExistingPullRequestNotice: View {
    let pullRequest: PullRequestSummary

    @Environment(GitHubModel.self) private var model

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
        HStack(spacing: DS.Space.md) {
            PullRequestStateIcon(state: pullRequest.state, isDraft: pullRequest.isDraft, size: DS.Size.navIcon)
            Text("This branch already has \(pullRequest.reference).")
                .font(.dsBody)
                .foregroundStyle(.dsTextSecondary)
                .lineLimit(1)
            Spacer(minLength: DS.Space.md)
            Button("Open") { model.openInBrowser(pullRequest) }
                .buttonStyle(.ds(.ghost))
        }
        .padding(.leading, DS.Space.lg)
        .padding(.trailing, DS.Space.xs)
        .padding(.vertical, DS.Space.xs)
        .background(.dsSurfaceSunken, in: shape)
        .overlay { shape.strokeBorder(.dsSeparator, lineWidth: 1) }
    }
}
