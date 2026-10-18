import GitHub
import SwiftUI

/// Finishing a review (GitHub's "Review changes"): a summary, then Comment, Approve or Request
/// Changes. Submitting can't be taken back, so this sheet is the confirmation. A pending review can
/// also be discarded from here, after its own confirmation.
struct SubmitReviewSheet: View {
    let model: PullRequestPageModel

    @Environment(\.dismiss) private var dismiss
    @State private var body_ = ""
    @State private var event = ReviewEvent.comment
    @State private var isConfirmingDiscard = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Review \(model.reference.display)")
                    .font(.dsHeadline)
                    .foregroundStyle(.dsTextPrimary)
                Spacer()
                IconButton("Close", systemImage: "xmark") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(.leading, DS.Space.xl)
            .padding(.trailing, DS.Space.md)
            .frame(height: DS.Window.headerHeight + DS.Space.md)
            SeparatorLine()
            VStack(alignment: .leading, spacing: DS.Space.lg) {
                if model.pendingCommentCount > 0 {
                    Text("\(model.pendingCommentCount) pending comment\(model.pendingCommentCount == 1 ? "" : "s") will be published with this review.")
                        .font(.dsBody)
                        .foregroundStyle(.dsTextSecondary)
                }
                GitHubCommentComposer(text: $body_, placeholder: "Leave a summary (optional). Markdown works.", focusesOnAppear: true) {
                    EmptyView()
                }
                VStack(alignment: .leading, spacing: DS.Space.sm) {
                    ForEach(ReviewEvent.allCases, id: \.self) { option in
                        option_(option)
                    }
                }
                if let error = model.actionError {
                    Text(error.localizedDescription)
                        .font(.dsBody)
                        .foregroundStyle(.dsDanger)
                }
            }
            .padding(DS.Space.xl)
            SeparatorLine()
            HStack(spacing: DS.Space.md) {
                if model.page?.pendingReview != nil {
                    Button("Discard Review…", role: .destructive) { isConfirmingDiscard = true }
                        .buttonStyle(.ds(.ghost, size: .medium))
                }
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(.ds(.ghost, size: .medium))
                Button(model.busy.contains("review") ? "Submitting…" : "Submit Review") {
                    Task {
                        if await model.submitReview(event, body: body_) { dismiss() }
                    }
                }
                .buttonStyle(.ds(.primary, size: .medium))
                .keyboardShortcut(.defaultAction)
                .disabled(!canSubmit || model.busy.contains("review"))
            }
            .padding(.horizontal, DS.Space.xl)
            .padding(.vertical, DS.Space.lg)
        }
        .frame(width: CreatePullRequestLayout.width)
        .background(.dsBackground)
        .confirmationDialog("Discard your pending review?", isPresented: $isConfirmingDiscard, titleVisibility: .visible) {
            Button("Discard \(model.pendingCommentCount) Comment\(model.pendingCommentCount == 1 ? "" : "s")", role: .destructive) {
                Task {
                    await model.discardReview()
                    dismiss()
                }
            }
        } message: {
            Text("Your pending comments are deleted on GitHub. This can't be undone.")
        }
        .onAppear { model.actionError = nil }
    }

    /// A comment-only review needs something to say: a summary or pending comments.
    private var canSubmit: Bool {
        guard let page = model.page else { return false }
        if event != .comment, !page.viewerCanApprove { return false }
        return event != .comment || model.pendingCommentCount > 0 || !body_.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func option_(_ option: ReviewEvent) -> some View {
        let disabled = option != .comment && model.page?.viewerCanApprove == false
        return Button {
            event = option
        } label: {
            HStack(alignment: .top, spacing: DS.Space.md) {
                Image(systemName: event == option ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(event == option ? Color.dsAccent : .dsTextTertiary)
                VStack(alignment: .leading, spacing: DS.Space.xxs) {
                    Text(title(option))
                        .font(.dsBodyMedium)
                        .foregroundStyle(disabled ? .dsTextTertiary : .dsTextPrimary)
                    Text(disabled ? "You can't \(option == .approve ? "approve" : "request changes on") your own pull request." : detail(option))
                        .font(.dsCaption)
                        .foregroundStyle(.dsTextTertiary)
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }

    private func title(_ option: ReviewEvent) -> String {
        switch option {
        case .comment: "Comment"
        case .approve: "Approve"
        case .requestChanges: "Request Changes"
        }
    }

    private func detail(_ option: ReviewEvent) -> String {
        switch option {
        case .comment: "General feedback without explicit approval."
        case .approve: "Give your approval to merge these changes."
        case .requestChanges: "Feedback that must be addressed before merging."
        }
    }
}
