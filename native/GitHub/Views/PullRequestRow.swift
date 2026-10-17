import GitHub
import SwiftUI

/// One pull request in the list (Factory `PullRequestSummaryRow`): state glyph, title, size and
/// checks on the first line; reference, branch, author, age and review status under it. Clicking
/// opens it on GitHub, the checks glyph opens the failing check, and hovering offers the rest.
struct PullRequestRow: View {
    let pullRequest: PullRequestSummary
    var showsRepository = true

    @Environment(GitHubModel.self) private var model
    @State private var isHovered = false

    var body: some View {
        HStack(alignment: .top, spacing: DS.Space.md) {
            PullRequestStateIcon(state: pullRequest.state, isDraft: pullRequest.isDraft)
                .padding(.top, DS.Space.xxs)
            VStack(alignment: .leading, spacing: DS.Space.xs) {
                HStack(spacing: DS.Space.lg) {
                    Text(pullRequest.title)
                        .font(.dsCalloutBook)
                        .foregroundStyle(.dsTextPrimary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if let additions = pullRequest.additions, let deletions = pullRequest.deletions {
                        DiffStatLabel(added: additions, removed: deletions)
                    }
                    if let checks = pullRequest.checks {
                        ChecksButton(pullRequest: pullRequest, checks: checks)
                            .padding(.vertical, -DS.Space.xxs)
                    }
                }
                .frame(minHeight: DS.Size.rowLeading + DS.Space.xs)
                metadata
                    .overlay(alignment: .trailing) {
                        if isHovered { hoverActions }
                    }
            }
        }
        .padding(DS.Space.md)
        .contentShape(.rect)
        .onTapGesture { model.openInBrowser(pullRequest) }
        .background {
            RoundedRectangle(cornerRadius: DS.Radius.row, style: .continuous)
                .fill(isHovered ? .dsHover : .clear)
        }
        .trackHover($isHovered)
        .contextMenu { PullRequestActionsMenu(pullRequest: pullRequest) }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(.isLink)
        .accessibilityAction { model.openInBrowser(pullRequest) }
    }

    private var metadata: some View {
        HStack(spacing: DS.Space.lg) {
            Text(showsRepository ? pullRequest.reference : "#\(pullRequest.number)")
                .foregroundStyle(.dsTextTertiary)
                .lineLimit(1)
                .fixedSize()
            if let branch = pullRequest.headRefName {
                HStack(spacing: DS.Space.xs) {
                    Image(systemName: "arrow.triangle.branch")
                        .font(.system(size: DS.Size.navIcon - DS.Space.xs))
                    Text(branch)
                        .font(.dsMonoCaption)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .foregroundStyle(.dsTextSecondary)
                .help(branch)
                .layoutPriority(-1)
            }
            if let author = pullRequest.author, author.login != model.currentLogin {
                Text(author.login)
                    .foregroundStyle(.dsTextSecondary)
                    .lineLimit(1)
                    .layoutPriority(-1)
            }
            TimelineView(.everyMinute) { context in
                Text(DSFormat.compactAge(pullRequest.updatedAt, now: context.date))
                    .monospacedDigit()
                    .foregroundStyle(.dsTextTertiary)
                    .fixedSize()
                    .help("Updated \(pullRequest.updatedAt.formatted(.relative(presentation: .named)))")
            }
            ReviewStatusText(pullRequest: pullRequest)
            Spacer(minLength: 0)
        }
        .font(.dsCaption)
    }

    private var hoverActions: some View {
        HStack(spacing: DS.Space.xxs) {
            if model.canOpenAsTask, pullRequest.state == .open {
                IconButton("Open as Task", systemImage: "arrow.down.to.line.compact") {
                    model.requestOpenAsTask(pullRequest)
                }
            }
            IconButton("Copy URL", systemImage: "link") {
                model.copyURL(pullRequest)
            }
            IconButton("Open on GitHub", systemImage: "arrow.up.right") {
                model.openInBrowser(pullRequest)
            }
        }
        // A small floating toolbar, opaque so the metadata under it doesn't show through.
        .background(.dsSurface, in: RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                .strokeBorder(.dsSeparator, lineWidth: 1)
        }
    }

    private var accessibilityLabel: String {
        var parts = [pullRequest.title, pullRequest.reference]
        if let status = ReviewStatusText.status(of: pullRequest) { parts.append(status.label) }
        if let checks = pullRequest.checks { parts.append(ChecksIndicator.summary(checks)) }
        return parts.joined(separator: ", ")
    }
}
