import GitHub
import SwiftUI

/// A pull request at a glance, for a session's header: its state, number and checks, whose glyph
/// opens the failing check. Clicking the rest opens the pull request, in Native or on GitHub as
/// Settings say. A sidebar row has its own, smaller badge (`TaskPullRequestBadge`).
struct PullRequestBadge: View {
    let pullRequest: PullRequestSummary

    @Environment(GitHubModel.self) private var model
    @State private var isHovered = false

    var body: some View {
        regular
            .contextMenu { PullRequestActionsMenu(pullRequest: pullRequest) }
    }

    private var checks: CheckSummary? {
        pullRequest.state == .open ? pullRequest.checks : nil
    }

    private var regular: some View {
        let shape = RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous)
        return HStack(spacing: 0) {
            Button {
                model.open(pullRequest)
            } label: {
                HStack(spacing: DS.Space.xs) {
                    PullRequestStateIcon(state: pullRequest.state, isDraft: pullRequest.isDraft, size: DS.Size.navIcon)
                    Text(verbatim: "#\(pullRequest.number)")
                        .font(.dsMonoCaption)
                        .foregroundStyle(.dsTextPrimary)
                }
                .padding(.leading, DS.Space.sm)
                .padding(.trailing, checks == nil ? DS.Space.sm : DS.Space.xs)
                .frame(maxHeight: .infinity)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .help(summary)
            .accessibilityLabel(summary)
            if let checks {
                SeparatorLine(axis: .vertical)
                ChecksButton(pullRequest: pullRequest, checks: checks)
                    .padding(.horizontal, DS.Space.xxs)
            }
        }
        .frame(height: DS.Size.controlXS - DS.Space.xs)
        .background(isHovered ? .dsHover : .dsSurface, in: shape)
        .overlay { shape.strokeBorder(isHovered ? .dsBorderHover : .dsBorder, lineWidth: 1) }
        .clipShape(shape)
        .trackHover($isHovered)
    }

    private var summary: String {
        var parts = ["\(pullRequest.reference): \(pullRequest.title)"]
        let state = PullRequestStateIcon(state: pullRequest.state, isDraft: pullRequest.isDraft).label
        parts.append(ReviewStatusText.status(of: pullRequest).map { "\(state), \($0.label.lowercased())" } ?? state)
        if let checks {
            parts.append(ChecksIndicator.summary(checks))
        }
        return parts.joined(separator: "\n")
    }
}

#if NATIVE_PREVIEWS_WIP
#Preview("Pull request badges") {
    let pullRequests = Array(PullRequestPreviewFixtures.inbox.all.prefix(5))
    DSPreviewPair {
        VStack(alignment: .leading, spacing: DS.Space.lg) {
            ForEach(pullRequests) { pullRequest in
                PullRequestBadge(pullRequest: pullRequest)
            }
        }
    }
    .environment(GitHubModel.preview(inbox: PullRequestPreviewFixtures.inbox))
}
#endif
