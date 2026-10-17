import GitHub
import SwiftUI

/// A pull request at a glance, for a task: its state and checks. `.compact` fits a sidebar row's
/// trailing edge; `.regular` adds the number, for the session header, and its checks glyph opens
/// the failing check. Clicking the rest opens the pull request on GitHub.
struct PullRequestBadge: View {
    enum Style {
        case compact
        case regular
    }

    let pullRequest: PullRequestSummary
    var style: Style = .regular

    @Environment(GitHubModel.self) private var model
    @State private var isHovered = false

    var body: some View {
        Group {
            switch style {
            case .compact: compact
            case .regular: regular
            }
        }
        .contextMenu { PullRequestActionsMenu(pullRequest: pullRequest) }
    }

    private var checks: CheckSummary? {
        pullRequest.state == .open ? pullRequest.checks : nil
    }

    private var compact: some View {
        Button {
            model.openInBrowser(pullRequest)
        } label: {
            HStack(spacing: DS.Space.xxs) {
                PullRequestStateIcon(state: pullRequest.state, isDraft: pullRequest.isDraft, size: DS.Size.navIcon)
                if let checks {
                    ChecksIndicator(checks: checks)
                }
            }
            .padding(.horizontal, DS.Space.xxs)
            .frame(height: DS.Size.rowLeading)
            .background(
                isHovered ? .dsHover : .clear, in: RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous)
            )
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .trackHover($isHovered)
        .help(summary)
        .accessibilityLabel(summary)
    }

    private var regular: some View {
        let shape = RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous)
        return HStack(spacing: 0) {
            Button {
                model.openInBrowser(pullRequest)
            } label: {
                HStack(spacing: DS.Space.xs) {
                    PullRequestStateIcon(state: pullRequest.state, isDraft: pullRequest.isDraft, size: DS.Size.navIcon)
                    Text("#\(pullRequest.number)")
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
