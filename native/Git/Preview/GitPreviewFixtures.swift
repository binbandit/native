import ACP
import Git
import SwiftUI

/// Sample repository states for previews.
enum GitPreviewFixtures {
    static let branch = BranchStatus(
        head: .branch("brayden/git-support"), commit: "4f2c9e1a", upstream: "origin/brayden/git-support", ahead: 2,
        behind: 1)

    static let status = RepositoryStatus(
        branch: branch,
        changes: [
            FileChange(
                path: "native/Git/Model/GitStore.swift", kind: .added, area: .staged, stats: LineStats(additions: 84)),
            FileChange(
                path: "native/Views/SessionView.swift", kind: .modified, area: .staged,
                stats: LineStats(additions: 12, deletions: 3)),
            FileChange(
                path: "Packages/Git/Sources/Git/Git.swift", kind: .modified, area: .unstaged,
                stats: LineStats(additions: 31, deletions: 9)),
            FileChange(path: "docs/old-notes.md", kind: .deleted, area: .unstaged, stats: LineStats(deletions: 42)),
            FileChange(
                path: "native/Git/Views/GitBranchBadge.swift", originalPath: "native/Git/BranchBadge.swift",
                kind: .renamed, area: .staged, stats: LineStats(additions: 2, deletions: 2)),
            FileChange(
                path: "design/git/inspector.png", kind: .untracked, area: .untracked, stats: LineStats(isBinary: true)),
            FileChange(path: "scratch notes.txt", kind: .untracked, area: .untracked, stats: LineStats(additions: 7)),
        ].sorted { $0.area < $1.area },
        totals: LineStats(additions: 136, deletions: 56)
    )

    static let diff = GitDiffContent.text(
        FileDiff(
            path: "native/Git/Model/GitStore.swift",
            oldText: nil,
            newText: """
                import Foundation
                import Git

                /// The app's entry point to git.
                @Observable
                final class GitStore {
                    private var models: [URL: GitRepositoryModel] = [:]

                    func model(for folder: URL) -> GitRepositoryModel {
                        models[folder] ?? GitRepositoryModel(folder: folder)
                    }
                }
                """
        ))

    static var model: GitRepositoryModel {
        GitRepositoryModel(folder: URL(filePath: "/Users/me/native"), fixedStatus: status, diff: diff)
    }
}

#Preview("Changes inspector") {
    HStack(spacing: 0) {
        ForEach([ColorScheme.light, .dark], id: \.self) { scheme in
            GitChangesInspector(model: GitPreviewFixtures.model, onCreatePullRequest: {})
                .frame(width: GitMetrics.inspectorIdealWidth, height: 720)
                .environment(\.colorScheme, scheme)
        }
    }
}

#Preview("Commit popover") {
    @Previewable @State var isPresented = true
    GitCommitPopover(model: GitPreviewFixtures.model, isPresented: $isPresented, onCreatePullRequest: {})
}

#Preview("Branch badge") {
    VStack(alignment: .leading, spacing: DS.Space.md) {
        GitBranchBadge(branch: GitPreviewFixtures.branch, isDirty: true)
        GitBranchBadge(branch: BranchStatus(head: .branch("main"), commit: "abc", upstream: "origin/main"))
        GitBranchBadge(branch: BranchStatus(head: .detached, commit: "9e8d7c6b5a"), isDirty: true)
    }
    .padding(DS.Space.xl)
    .background(.dsBackground)
}
