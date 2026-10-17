import Git
import SwiftUI

/// The trailing indicators of a sidebar task row, from the features that know about the task: its
/// pull request, its working tree's state against its branch, and its context usage. One line,
/// each part showing only when it has something to say.
struct AppTaskRowAccessory: View {
    let summary: SessionSummary

    @Environment(GitStore.self) private var git

    var body: some View {
        let folder = URL(filePath: summary.info.cwd, directoryHint: .isDirectory)
        let repository = git.model(for: folder)
        HStack(spacing: DS.Space.xs) {
            if let branch = repository.branch?.name {
                TaskPullRequestBadge(directory: folder, branch: branch)
            }
            GitBranchBadge.Live(model: repository, font: .dsMicro, style: .compact)
            SessionContextUsage(summary: summary)
        }
    }
}
