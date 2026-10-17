import GitHub
import SwiftUI

/// Says the branch already has an open pull request; the sheet offers it instead of a duplicate.
struct ExistingPullRequestNotice: View {
    let pullRequest: PullRequestSummary

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
        HStack(spacing: DS.Space.md) {
            PullRequestStateIcon(state: pullRequest.state, isDraft: pullRequest.isDraft, size: DS.Size.navIcon)
            Text("This branch already has an open pull request, \(pullRequest.reference).")
                .font(.dsBody)
                .foregroundStyle(.dsTextSecondary)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, DS.Space.lg)
        .frame(minHeight: DS.Size.controlMD)
        .background(.dsSurfaceSunken, in: shape)
        .overlay { shape.strokeBorder(.dsSeparator, lineWidth: 1) }
    }
}
