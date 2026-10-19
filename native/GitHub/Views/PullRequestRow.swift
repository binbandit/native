import GitHub
import SwiftUI

/// One pull request in the list: state glyph, title, size and
/// checks on the first line; reference, branch, author, age and review status under it. Clicking
/// opens it (in Native or on GitHub, as Settings say), the checks glyph opens the failing check, and
/// hovering offers the rest: comment, merge, close or reopen, open as a task. Under it, a quick
/// comment box when open, and what an action from here is doing.
struct PullRequestRow: View {
    let pullRequest: PullRequestSummary
    var showsRepository = true

    @Environment(GitHubModel.self) private var model
    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            summary
            if model.commentingOn == pullRequest.url {
                PullRequestQuickComment(pullRequest: pullRequest)
                    .padding(.leading, DS.Size.rowLeading + DS.Space.md)
                    .padding([.horizontal, .bottom], DS.Space.md)
            }
            if let activity = model.rowActivity[pullRequest.url] {
                PullRequestRowStatus(activity: activity) { model.report(nil, for: pullRequest.url) }
                    .padding(.leading, DS.Size.rowLeading + DS.Space.md * 2)
                    .padding(.trailing, DS.Space.md)
                    .padding(.bottom, DS.Space.sm)
            }
        }
    }

    private var summary: some View {
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
                        // Touch has no hover, so the actions stay out; the context menu has them too.
                        if isHovered || DS.isTouchPlatform { hoverActions }
                    }
            }
        }
        .padding(DS.Space.md)
        .contentShape(.rect)
        .onTapGesture { model.open(pullRequest) }
        .background {
            RoundedRectangle(cornerRadius: DS.Radius.row, style: .continuous)
                .fill(isHovered ? .dsHover : .clear)
        }
        .trackHover($isHovered)
        .contextMenu { PullRequestActionsMenu(pullRequest: pullRequest, offersListActions: true) }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(.isLink)
        .accessibilityAction { model.open(pullRequest) }
        // The hover buttons, for VoiceOver and keyboard users, who never hover.
        .accessibilityActions {
            Button("Comment") { model.toggleQuickComment(pullRequest) }
            if pullRequest.state == .open, !pullRequest.isDraft {
                Button("Merge…") { model.requestMerge(pullRequest) }
            }
            if pullRequest.state == .open {
                Button("Close Pull Request") { Task { await model.setOpen(false, pullRequest) } }
            } else if pullRequest.state == .closed {
                Button("Reopen Pull Request") { Task { await model.setOpen(true, pullRequest) } }
            }
            if model.canOpenAsTask, pullRequest.state == .open {
                Button("Open as Task…") { model.requestOpenAsTask(pullRequest) }
            }
        }
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
            if let state = pullRequest.mergeState {
                Label(state.summary, systemImage: "list.number")
                    .foregroundStyle(.dsInfo)
                    .lineLimit(1)
                    .fixedSize()
            }
            Spacer(minLength: 0)
        }
        .font(.dsCaption)
    }

    private var hoverActions: some View {
        let isBusy: Bool = if case .working? = model.rowActivity[pullRequest.url] { true } else { false }
        return HStack(spacing: DS.Space.xxs) {
            IconButton("Comment", systemImage: "text.bubble", isActive: model.commentingOn == pullRequest.url) {
                model.toggleQuickComment(pullRequest)
            }
            if pullRequest.state == .open, !pullRequest.isDraft {
                IconButton("Merge…", systemImage: "arrow.triangle.merge") {
                    model.requestMerge(pullRequest)
                }
                .disabled(isBusy)
            }
            if pullRequest.state == .open {
                IconButton("Close Pull Request", systemImage: "xmark.circle") {
                    Task { await model.setOpen(false, pullRequest) }
                }
                .disabled(isBusy)
            } else if pullRequest.state == .closed {
                IconButton("Reopen Pull Request", systemImage: "arrow.uturn.backward.circle") {
                    Task { await model.setOpen(true, pullRequest) }
                }
                .disabled(isBusy)
            }
            if model.canOpenAsTask, pullRequest.state == .open {
                IconButton("Open as Task", systemImage: "arrow.down.to.line.compact") {
                    model.requestOpenAsTask(pullRequest)
                }
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
        if let state = pullRequest.mergeState { parts.append(state.summary) }
        return parts.joined(separator: ", ")
    }
}
