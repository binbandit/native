import GitHub
import SwiftUI

/// The checks glyph as a button: a failing x opens the failing check's log directly, anything else
/// the pull request's Checks tab.
struct ChecksButton: View {
    let pullRequest: PullRequestSummary
    let checks: CheckSummary

    @Environment(GitHubModel.self) private var model
    @State private var isHovered = false

    var body: some View {
        Button {
            Task { await model.openChecks(pullRequest) }
        } label: {
            ChecksIndicator(checks: checks)
                .padding(DS.Space.xxs)
                .background(
                    isHovered ? .dsHover : .clear,
                    in: RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous)
                )
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .trackHover($isHovered)
        .help(
            ChecksIndicator.summary(checks) + (checks.state == .failing ? "\nOpen the failing check" : "\nOpen checks"))
    }
}

#if NATIVE_PREVIEWS_WIP
#Preview("Checks button") {
    let pullRequest = PullRequestPreviewFixtures.inbox.authored[0]
    DSPreviewPair {
        HStack(spacing: DS.Space.lg) {
            ChecksButton(pullRequest: pullRequest, checks: CheckSummary(state: .passing, passed: 9, skipped: 1))
            ChecksButton(pullRequest: pullRequest, checks: CheckSummary(state: .failing, passed: 9, failed: 1))
            ChecksButton(pullRequest: pullRequest, checks: CheckSummary(state: .pending, passed: 6, pending: 4))
        }
    }
    .environment(GitHubModel.preview())
}
#endif
