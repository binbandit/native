import GitHub
import SwiftUI

/// One conversation entry: comments and review summaries as cards, commits and events as quiet
/// one-line rows between them (GitHub's timeline).
struct PullRequestTimelineRow: View {
    let item: PullRequestTimelineItem
    let model: PullRequestPageModel

    var body: some View {
        switch item {
        case .comment(let comment):
            PullRequestCommentCard(
                author: comment.author, date: comment.createdAt, body: comment.body, url: comment.url,
                edited: comment.lastEditedAt != nil)
        case .review(let review):
            reviewRow(review)
        case .commit(let commit):
            eventLine(systemImage: "smallcircle.filled.circle", tint: .dsTextTertiary, date: commit.date) {
                Text(
                    "\(Text(commit.headline).foregroundStyle(.dsTextPrimary))  \(Text(commit.abbreviatedOid).font(.dsMonoCaption))"
                )
            }
        case .event(let event):
            eventLine(systemImage: symbol(for: event.kind), tint: tint(for: event.kind), date: event.date) {
                Text("\(Text(event.actor ?? "Someone").foregroundStyle(.dsTextPrimary)) \(description(of: event.kind))")
            }
        case .other:
            EmptyView()
        }
    }

    @ViewBuilder private func reviewRow(_ review: PullRequestTimelineItem.Review) -> some View {
        let verdict = verdict(review.state)
        if review.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            eventLine(systemImage: verdict.symbol, tint: verdict.tint, date: review.submittedAt) {
                Text(
                    "\(Text(review.author ?? "Someone").foregroundStyle(.dsTextPrimary)) \(verdict.phrase)\(commentSuffix(review))"
                )
            }
        } else {
            PullRequestCommentCard(
                author: review.author, date: review.submittedAt, body: review.body, url: review.url, edited: false,
                badge: (verdict.label, verdict.tone))
        }
    }

    private func commentSuffix(_ review: PullRequestTimelineItem.Review) -> String {
        review.commentCount > 0 ? " with \(review.commentCount) comment\(review.commentCount == 1 ? "" : "s")" : ""
    }

    private func eventLine(systemImage: String, tint: Color, date: Date?, @ViewBuilder text: () -> Text) -> some View {
        HStack(spacing: DS.Space.md) {
            Image(systemName: systemImage)
                .font(.system(size: DS.Size.navIcon - DS.Space.xxs))
                .foregroundStyle(tint)
                .frame(width: DS.Size.rowLeading)
            text()
                .font(.dsBody)
                .foregroundStyle(.dsTextSecondary)
                .lineLimit(1)
            Spacer(minLength: DS.Space.md)
            if let date {
                Text(DSFormat.compactAge(date, now: .now))
                    .font(.dsCaption)
                    .foregroundStyle(.dsTextTertiary)
            }
        }
        .padding(.horizontal, DS.Space.lg)
    }

    private func verdict(
        _ state: PullRequestReview.State
    ) -> (label: String, phrase: String, symbol: String, tint: Color, tone: Badge.Tone) {
        switch state {
        case .approved: ("Approved", "approved these changes", "checkmark.circle", .dsSuccess, .success)
        case .changesRequested: ("Changes requested", "requested changes", "exclamationmark.circle", .dsDanger, .danger)
        case .dismissed: ("Dismissed", "had a review dismissed", "slash.circle", .dsTextTertiary, .neutral)
        case .commented, .pending, .other: ("Reviewed", "reviewed", "eye", .dsTextTertiary, .neutral)
        }
    }

    private func description(of kind: PullRequestTimelineItem.Event.Kind) -> String {
        switch kind {
        case .forcePushed(let before, let after): "force-pushed \(before ?? "?") to \(after ?? "?")"
        case .labeled(let label): "added the \(label.name) label"
        case .unlabeled(let label): "removed the \(label.name) label"
        case .reviewRequested(let reviewer): "requested a review\(reviewer.map { " from \($0)" } ?? "")"
        case .merged(let commit, let into): "merged \(commit ?? "")\(into.map { " into \($0)" } ?? "")"
        case .closed: "closed this"
        case .reopened: "reopened this"
        case .readyForReview: "marked this ready for review"
        case .convertedToDraft: "converted this to a draft"
        case .renamed(let from, let to): "renamed this from \u{201C}\(from)\u{201D} to \u{201C}\(to)\u{201D}"
        }
    }

    private func symbol(for kind: PullRequestTimelineItem.Event.Kind) -> String {
        switch kind {
        case .forcePushed: "arrow.up.circle"
        case .labeled, .unlabeled: "tag"
        case .reviewRequested: "person.crop.circle.badge.questionmark"
        case .merged: "arrow.triangle.merge"
        case .closed: "xmark.circle"
        case .reopened: "arrow.uturn.left.circle"
        case .readyForReview: "eye"
        case .convertedToDraft: "pencil.circle"
        case .renamed: "pencil"
        }
    }

    private func tint(for kind: PullRequestTimelineItem.Event.Kind) -> Color {
        switch kind {
        case .merged: .dsMerged
        case .closed: .dsDanger
        default: .dsTextTertiary
        }
    }
}
