import GitHub
import SwiftUI

/// Where the pull request stands, at the end of the conversation (GitHub's merge box): reviews,
/// checks and mergeability, then the next step, named for what it does: "Merge When Ready" for a
/// merge queue or auto-merge, exactly how it merges otherwise, or why the user can't.
struct PullRequestMergeBox: View {
    let model: PullRequestPageModel
    let page: PullRequestPage

    var body: some View {
        Card(padding: 0) {
            VStack(alignment: .leading, spacing: 0) {
                row(review.symbol, review.tint, review.text)
                if let checks = page.checks {
                    SeparatorLine()
                    HStack(spacing: DS.Space.md) {
                        ChecksIndicator(checks: checks)
                            .frame(width: DS.Size.rowLeading)
                        Text(ChecksIndicator.summary(checks))
                            .font(.dsBody)
                            .foregroundStyle(.dsTextPrimary)
                        Spacer(minLength: DS.Space.md)
                        Button(checks.state == .failing ? "View Failing Checks" : "View Checks") { model.tab = .checks }
                            .buttonStyle(.ds(.ghost))
                    }
                    .padding(.horizontal, DS.Space.lg)
                    .padding(.vertical, DS.Space.sm)
                }
                SeparatorLine()
                mergeRow
            }
        }
    }

    private var review: (symbol: String, tint: Color, text: String) {
        switch page.reviewDecision {
        case .approved: ("checkmark.circle", .dsSuccess, "Approved")
        case .changesRequested: ("exclamationmark.circle", .dsDanger, "Changes requested")
        case .reviewRequired:
            ("person.crop.circle.badge.questionmark", .dsWarning, "Review required" + requestedSuffix)
        case .other, nil:
            page.requestedReviewers.isEmpty
                ? ("person.crop.circle", .dsTextTertiary, "No review required")
                : (
                    "person.crop.circle.badge.questionmark", .dsTextTertiary,
                    "Waiting on a review from \(page.requestedReviewers.joined(separator: ", "))"
                )
        }
    }

    private var requestedSuffix: String {
        page.requestedReviewers.isEmpty ? "" : ", waiting on \(page.requestedReviewers.joined(separator: ", "))"
    }

    private func row(_ symbol: String, _ tint: Color, _ text: String) -> some View {
        HStack(spacing: DS.Space.md) {
            Image(systemName: symbol)
                .foregroundStyle(tint)
                .frame(width: DS.Size.rowLeading)
            Text(text)
                .font(.dsBody)
                .foregroundStyle(.dsTextPrimary)
                .lineLimit(2)
            Spacer(minLength: DS.Space.md)
        }
        .padding(.horizontal, DS.Space.lg)
        .padding(.vertical, DS.Space.sm)
    }

    @ViewBuilder private var mergeRow: some View {
        HStack(spacing: DS.Space.md) {
            Image(systemName: mergeSymbol)
                .foregroundStyle(mergeTint)
                .frame(width: DS.Size.rowLeading)
            Text(mergeText)
                .font(.dsBody)
                .foregroundStyle(.dsTextSecondary)
                .lineLimit(2)
            Spacer(minLength: DS.Space.md)
            if page.isOpen, page.viewerCanMerge, !page.isDraft, let plan = model.mergePlan {
                Button(
                    plan.state == nil ? plan.title + "…" : "Manage…",
                    systemImage: plan.state == nil ? "arrow.triangle.merge" : "list.number"
                ) {
                    model.isMergeSheetPresented = true
                }
                .buttonStyle(.ds(.secondary))
            }
        }
        .padding(.horizontal, DS.Space.lg)
        .padding(.vertical, DS.Space.sm)
    }

    private var mergeText: String {
        switch page.state {
        case .merged: return "Merged into \(page.baseRefName)."
        case .closed: return "Closed without merging."
        case .open, .other: break
        }
        if page.isDraft { return "This is a draft; it can't be merged until it's marked ready for review." }
        if !page.viewerCanMerge {
            return
                "Only people with write access to \(page.reference.repository) can merge it. Your account has \(page.permission.rawValue.lowercased()) access."
        }
        if page.mergeable == .conflicting { return "This branch has conflicts that must be resolved." }
        if let state = page.mergeState {
            return switch state {
            case .queued: "\(state.summary) in \(page.baseRefName)'s merge queue."
            case .autoMerge:
                "Auto-merge is on: it merges into \(page.baseRefName) once required checks and reviews pass."
            }
        }
        if page.isMergeQueueEnabled {
            if let reason = page.removedFromQueueReason {
                return "Removed from the merge queue: \(reason). Merge When Ready adds it back."
            }
            return
                "\(page.baseRefName) merges through a merge queue: Merge When Ready adds it, and the queue merges it once its checks pass."
        }
        return switch page.mergeStatus {
        case .clean, .hasHooks: "Ready to merge."
        case .unstable: "Mergeable, though some checks that aren't required failed."
        case .blocked: "Blocked by branch protection: approvals or required checks are missing."
        case .behind: "\(page.headRefName) is behind \(page.baseRefName) and must be updated first."
        case .dirty: "This branch has conflicts that must be resolved."
        case .draft, .unknown, .other, nil: "GitHub is still checking whether it can merge."
        }
    }

    private var mergeSymbol: String {
        if page.state == .merged { return "arrow.triangle.merge" }
        if page.mergeState != nil { return "list.number" }
        return page.viewerCanMerge ? "arrow.triangle.merge" : "lock"
    }

    private var mergeTint: Color {
        switch page.state {
        case .merged: .dsMerged
        case .closed: .dsDanger
        default: page.mergeStatus == .clean || page.mergeStatus == .hasHooks ? .dsSuccess : .dsTextTertiary
        }
    }
}
