import GitHub
import SwiftUI

/// A conversation on lines: its comments, a reply box, and Resolve. A resolved one folds to one
/// line until opened, as on GitHub.
struct PullRequestReviewThreadView: View {
    let model: PullRequestPageModel
    let thread: ReviewThread
    /// Names the lines, for conversations shown away from them (outdated ones).
    let showsAnchor: Bool

    @State private var isExpanded = false
    @State private var isReplying = false
    @State private var editing: ReviewComment.ID?
    @State private var editText = ""

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
        VStack(alignment: .leading, spacing: 0) {
            header
            if !thread.isResolved || isExpanded {
                ForEach(thread.comments) { comment in
                    SeparatorLine()
                    commentRow(comment)
                }
                SeparatorLine()
                footer
            }
        }
        .background(.dsSurface, in: shape)
        .overlay {
            shape.strokeBorder(thread.isPending ? Color.dsAttention.opacity(0.5) : Color.dsSeparator, lineWidth: 1)
        }
        .clipShape(shape)
        .codeTextStyle(.block)
    }

    private var header: some View {
        Button {
            withAnimation(.dsDisclosure) { isExpanded.toggle() }
        } label: {
            HStack(spacing: DS.Space.sm) {
                Image(systemName: thread.isResolved ? "checkmark.circle.fill" : "text.bubble")
                    .foregroundStyle(thread.isResolved ? Color.dsSuccess : .dsTextTertiary)
                Text(title)
                    .foregroundStyle(.dsTextSecondary)
                    .lineLimit(1)
                if thread.isOutdated { Badge("Outdated", tone: .warning, style: .soft) }
                if thread.isPending { Badge("Pending", tone: .attention, style: .soft) }
                Spacer(minLength: DS.Space.md)
                if thread.isResolved {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .foregroundStyle(.dsTextTertiary)
                }
            }
            .font(.dsCaption)
            .padding(.horizontal, DS.Space.md)
            .padding(.vertical, DS.Space.sm)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(!thread.isResolved)
    }

    private var title: String {
        var parts: [String] = []
        if showsAnchor { parts.append(thread.anchor?.lineDescription.capitalizedFirstLetter ?? "On the file") }
        if thread.isResolved {
            parts.append("Resolved" + (thread.resolvedBy.map { " by \($0)" } ?? ""))
        } else {
            parts.append("\(thread.comments.count) comment\(thread.comments.count == 1 ? "" : "s")")
        }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder private func commentRow(_ comment: ReviewComment) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.sm) {
            HStack(spacing: DS.Space.sm) {
                GitHubAuthorAvatar(login: comment.author)
                Text(comment.author ?? "ghost")
                    .font(.dsBodyMedium)
                    .foregroundStyle(.dsTextPrimary)
                Text(
                    DSFormat.compactAge(comment.createdAt, now: .now) + (comment.lastEditedAt == nil ? "" : " · edited")
                )
                .font(.dsCaption)
                .foregroundStyle(.dsTextTertiary)
                Spacer(minLength: DS.Space.md)
                commentMenu(comment)
            }
            if editing == comment.id {
                GitHubCommentComposer(
                    text: $editText, placeholder: "Edit your comment", isBusy: model.busy.contains(comment.id),
                    focusesOnAppear: true
                ) {
                    Button("Cancel") { editing = nil }
                        .buttonStyle(.ds(.ghost))
                    Button("Save") {
                        Task {
                            await model.update(comment, body: editText)
                            editing = nil
                        }
                    }
                    .buttonStyle(.ds(.primary))
                }
            } else {
                PullRequestMarkdownBody(source: comment.body, original: thread.anchor.map(model.lineText(for:)))
                    .padding(.leading, DS.Size.rowLeading + DS.Space.sm)
            }
        }
        .padding(DS.Space.md)
    }

    private func commentMenu(_ comment: ReviewComment) -> some View {
        Menu {
            if comment.viewerCanUpdate {
                Button("Edit", systemImage: "pencil") {
                    editText = comment.body
                    editing = comment.id
                }
            }
            if comment.viewerCanDelete {
                Button("Delete", systemImage: "trash", role: .destructive) {
                    Task { await model.delete(comment, in: thread) }
                }
            }
            if let url = comment.url {
                Button("Open on GitHub", systemImage: "arrow.up.right") { model.open(url) }
                Button("Copy Link", systemImage: "link") { model.gitHub?.copy(url.absoluteString) }
            }
        } label: {
            Image(systemName: "ellipsis")
                .frame(width: DS.Size.controlXS, height: DS.Size.controlXS)
                .contentShape(.rect)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .foregroundStyle(.dsTextSecondary)
        .accessibilityLabel("Comment Options")
    }

    @ViewBuilder private var footer: some View {
        if isReplying {
            GitHubCommentComposer(
                text: Binding(get: { model.replyDrafts[thread.id] ?? "" }, set: { model.replyDrafts[thread.id] = $0 }),
                placeholder: "Reply. Markdown works.", isBusy: model.busy.contains(thread.id), focusesOnAppear: true
            ) {
                Button("Cancel") { isReplying = false }
                    .buttonStyle(.ds(.ghost))
                Button(model.page?.pendingReview == nil ? "Reply" : "Add to Review") {
                    Task {
                        await model.reply(to: thread)
                        if model.replyDrafts[thread.id] == nil { isReplying = false }
                    }
                }
                .buttonStyle(.ds(.primary))
                .keyboardShortcut(.return, modifiers: .command)
                .disabled((model.replyDrafts[thread.id] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(DS.Space.md)
        } else {
            HStack(spacing: DS.Space.sm) {
                if thread.viewerCanReply {
                    Button("Reply", systemImage: "arrowshape.turn.up.left") { isReplying = true }
                        .buttonStyle(.ds(.ghost))
                }
                if thread.isResolved ? thread.viewerCanUnresolve : thread.viewerCanResolve {
                    Button(
                        thread.isResolved ? "Unresolve" : "Resolve Conversation",
                        systemImage: thread.isResolved ? "arrow.uturn.backward" : "checkmark"
                    ) {
                        Task { await model.setResolved(!thread.isResolved, thread) }
                    }
                    .buttonStyle(.ds(.ghost))
                    .disabled(model.busy.contains(thread.id))
                }
                Spacer(minLength: DS.Space.md)
                if model.canAskAgent, let anchor = thread.anchor, !thread.isResolved {
                    Menu {
                        PullRequestAskAgentButtons(model: model, anchor: anchor, thread: thread)
                    } label: {
                        Label("Ask an Agent", systemImage: "sparkles")
                    }
                    .menuStyle(.button)
                    .buttonStyle(.ds(.ghost))
                    .fixedSize()
                }
            }
            .padding(.horizontal, DS.Space.sm)
            .padding(.vertical, DS.Space.xs)
        }
    }
}

extension String {
    fileprivate var capitalizedFirstLetter: String {
        prefix(1).uppercased() + dropFirst()
    }
}
