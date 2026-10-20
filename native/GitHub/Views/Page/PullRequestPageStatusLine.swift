import GitHub
import SwiftUI

/// "Open · binbandit wants to merge ai/branch into main · ✓ Checks · Approved · Ready to merge".
struct PullRequestPageStatusLine: View {
    let page: PullRequestPage
    /// Drops the author and the merge explanation, for narrow panes.
    let compact: Bool
    /// Moves whole parts (state, branches, checks, review) to the next line when they don't fit,
    /// for a fixed width like a sheet's; otherwise it's one line at its natural width.
    var wraps = false

    var body: some View {
        let layout = wraps ? AnyLayout(FlowLayout(spacing: DS.Space.lg)) : AnyLayout(HStackLayout(spacing: DS.Space.lg))
        return layout {
            HStack(spacing: DS.Space.xs) {
                PullRequestStateIcon(state: page.state, isDraft: page.isDraft, size: DS.Size.navIcon)
                Text(stateTitle)
                    .font(.dsBodyMedium)
                    .foregroundStyle(stateTint)
            }
            HStack(spacing: DS.Space.xs) {
                if !compact, let author = page.author {
                    Text(author)
                        .foregroundStyle(.dsTextPrimary)
                }
                BranchChip(name: page.headRefName)
                Image(systemName: "arrow.right")
                    .font(.system(size: DS.Size.navIcon - DS.Space.xxs))
                    .foregroundStyle(.dsTextTertiary)
                    .accessibilityLabel("into")
                BranchChip(name: page.baseRefName)
            }
            if let checks = page.checks {
                HStack(spacing: DS.Space.xs) {
                    ChecksIndicator(checks: checks)
                    Text(ChecksIndicator.summary(checks).replacingOccurrences(of: "Checks: ", with: ""))
                        .foregroundStyle(.dsTextSecondary)
                        .lineLimit(1)
                }
            }
            if let review = reviewText {
                Text(review.label)
                    .foregroundStyle(review.tint)
            }
            if !compact, let merge = page.mergeVerdict {
                Text(merge.label)
                    .foregroundStyle(merge.tint)
                    .lineLimit(1)
            }
        }
        .font(.dsBody)
        .fixedSize(horizontal: !wraps, vertical: true)
    }

    private var stateTitle: String {
        switch page.state {
        case .merged: "Merged"
        case .closed: "Closed"
        case .open: page.isDraft ? "Draft" : "Open"
        case .other: "Pull request"
        }
    }

    private var stateTint: Color {
        switch page.state {
        case .merged: .dsMerged
        case .closed: .dsDanger
        case .open: page.isDraft ? .dsTextSecondary : .dsSuccess
        case .other: .dsTextSecondary
        }
    }

    private var reviewText: (label: String, tint: Color)? {
        guard page.isOpen else { return nil }
        return switch page.reviewDecision {
        case .approved: ("Approved", .dsSuccess)
        case .changesRequested: ("Changes requested", .dsDanger)
        case .reviewRequired: ("Review required", .dsTextTertiary)
        case .other, nil: nil
        }
    }
}
