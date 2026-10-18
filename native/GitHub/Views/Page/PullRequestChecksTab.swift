import GitHub
import SwiftUI

/// Every check on the head commit, problems first, each linking to its log (the reference app
/// `PullRequestChecks`).
struct PullRequestChecksTab: View {
    let model: PullRequestPageModel
    let page: PullRequestPage

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.lg) {
                if let checks = model.checks {
                    if checks.isEmpty {
                        EmptyStateView(
                            "No Checks", systemImage: "checklist",
                            message: "Nothing reported a status on this pull request's latest commit. Checks appear here when CI runs on a push.")
                    } else {
                        summary(checks)
                        Card(padding: 0) {
                            VStack(spacing: 0) {
                                ForEach(Array(sorted(checks).enumerated()), id: \.offset) { index, check in
                                    if index > 0 { SeparatorLine() }
                                    PullRequestCheckRow(check: check) { model.open($0) }
                                }
                            }
                        }
                    }
                } else if let error = model.checksError {
                    ErrorState(
                        "Checks couldn't load", suggestion: error.recoverySuggestion, details: error.stderr,
                        primary: .init("Try Again") { Task { await model.loadChecks(force: true) } })
                } else {
                    PullRequestListSkeleton()
                }
            }
            .padding(DS.Space.xl)
            .frame(maxWidth: DS.Size.contentColumn)
            .frame(maxWidth: .infinity)
        }
        .scrollContentBackground(.hidden)
        .task(id: page.headRefOid) { await model.loadChecks(force: true) }
    }

    private func summary(_ checks: [PullRequestCheck]) -> some View {
        HStack(spacing: DS.Space.md) {
            if let summary = CheckSummary(outcomes: checks.map(\.outcome)) {
                ChecksIndicator(checks: summary)
                Text(ChecksIndicator.summary(summary))
                    .font(.dsBodyMedium)
                    .foregroundStyle(.dsTextPrimary)
            }
            Spacer(minLength: DS.Space.md)
            Button("Refresh", systemImage: "arrow.clockwise") { Task { await model.loadChecks(force: true) } }
                .buttonStyle(.ds(.ghost))
                .disabled(model.isLoadingChecks)
        }
    }

    /// Failures first, then what's running, then the rest, as the reference app orders check groups.
    private func sorted(_ checks: [PullRequestCheck]) -> [PullRequestCheck] {
        let order: [CheckOutcome] = [.failed, .pending, .passed, .skipped]
        return checks.sorted { lhs, rhs in
            let left = order.firstIndex(of: lhs.outcome) ?? order.count
            let right = order.firstIndex(of: rhs.outcome) ?? order.count
            return left == right ? lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending : left < right
        }
    }
}

private struct PullRequestCheckRow: View {
    let check: PullRequestCheck
    let open: (URL) -> Void

    var body: some View {
        HStack(spacing: DS.Space.md) {
            if let summary = CheckSummary(outcomes: [check.outcome]) {
                ChecksIndicator(checks: summary)
            }
            VStack(alignment: .leading, spacing: DS.Space.xxs) {
                Text(check.name)
                    .font(.dsBody)
                    .foregroundStyle(.dsTextPrimary)
                    .lineLimit(1)
                Text(detail)
                    .font(.dsCaption)
                    .foregroundStyle(.dsTextTertiary)
                    .lineLimit(1)
            }
            Spacer(minLength: DS.Space.md)
            if let link = check.link {
                Button(check.outcome == .failed ? "View Log" : "Details") { open(link) }
                    .buttonStyle(.ds(check.outcome == .failed ? .secondary : .ghost))
            }
        }
        .padding(.horizontal, DS.Space.lg)
        .padding(.vertical, DS.Space.sm)
    }

    private var detail: String {
        var parts = [check.workflow, check.description].compactMap(\.self)
        if let started = check.startedAt, let finished = check.completedAt {
            parts.append(DSFormat.duration(finished.timeIntervalSince(started)))
        } else if check.outcome == .pending {
            parts.append("Running")
        }
        let state = check.state.replacingOccurrences(of: "_", with: " ").capitalized
        return ([state] + parts).joined(separator: " · ")
    }
}
