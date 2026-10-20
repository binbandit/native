import GitHub

extension PullRequestSummary {
    /// What VoiceOver says about a task's pull request: "pull request #12, open, checks: 1 failing,
    /// 9 passed". Checks only while it's open, where they still matter.
    var spokenSummary: String {
        let state = PullRequestStateIcon(state: state, isDraft: isDraft).label.lowercased()
        let checks = state == "open" ? checks.map { ChecksIndicator.summary($0).lowercased() } : nil
        return ["pull request #\(number)", state, checks].compactMap(\.self).joined(separator: ", ")
    }
}
