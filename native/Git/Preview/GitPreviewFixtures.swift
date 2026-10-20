#if DEBUG
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
        GitDiffText(
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
        GitRepositoryModel(folder: URL(filePath: "/Users/preview/Developer/native"), fixedStatus: status, diff: diff)
    }
}
#endif

#if DEBUG
extension GitPreviewFixtures {
    /// A working tree with nothing to commit.
    static var cleanModel: GitRepositoryModel {
        GitRepositoryModel(
            folder: URL(filePath: "/Users/preview/Developer/native"),
            fixedStatus: RepositoryStatus(branch: branch, changes: [], totals: LineStats()))
    }

    static let pushRejected = GitNotice(
        tone: .failure, title: "Push rejected",
        message: "origin/brayden/git-support has 2 commits this branch doesn't. Pull them, then push again.",
        detail: "! [rejected] brayden/git-support -> brayden/git-support (fetch first)", action: .pull)

    static let committed = GitNotice(tone: .success, title: "Committed 3 files", message: "4f2c9e1 Add GitStore")

    /// Projects, git and GitHub for Clean Up Merged, none of which run anything.
    static func cleanupServices(_ app: AppModel) -> GitCleanupServices {
        GitCleanupServices(
            app: app, git: GitStore(environment: { [:] }, settings: GitSettings(defaults: PreviewUserDefaults())),
            branchPrefix: { _ in "native/" }, pullRequests: { _, _ in .unavailable("Previews don't ask GitHub.") })
    }

    static let cleanupItems: [GitCleanupItem] = [
        GitCleanupItem(
            id: .worktree(URL(filePath: "/Users/preview/.native/worktrees/native/queue-follow-ups")), group: .worktrees,
            title: "queue-follow-ups", reason: "Merged via PR #212",
            pullRequest: URL(string: "https://github.com/binbandit/native/pull/212"),
            detail: "native/queue-follow-ups", location: "~/.native/worktrees/native/queue-follow-ups",
            bytes: 412_000_000,
            tasks: [
                GitCleanupItem.TaskReference(
                    key: SessionKey(
                        agent: AgentDefinition.ID(rawValue: "claude-code"), id: SessionID("0199f3a2-queue")),
                    title: "Queue follow-ups while a turn runs", isWorking: false)
            ]),
        GitCleanupItem(
            id: .worktree(URL(filePath: "/Users/preview/.native/worktrees/native/diff-wrapping")), group: .worktrees,
            title: "diff-wrapping", reason: "Merged into main", detail: "native/diff-wrapping",
            location: "~/.native/worktrees/native/diff-wrapping", warning: "3 uncommitted files", bytes: 96_000_000,
            isCheckedByDefault: false),
        GitCleanupItem(
            id: .branch("native/session-titles"), group: .branches, title: "native/session-titles",
            reason: "Merged via PR #208", detail: "at 9e8d7c6"),
        GitCleanupItem(
            id: .staleRecord(URL(filePath: "/Users/preview/.native/worktrees/native/old-sidebar")),
            group: .staleRecords, title: "old-sidebar", reason: "Its folder is gone"),
    ]

    /// A task's latest turn, which edited README.md and the inspector.
    static let turn = GitTurnReviewTarget(
        session: SessionKey(agent: AgentDefinition.ID(rawValue: "codex"), id: SessionID("0199f3a2-turn")),
        startedAt: .now.addingTimeInterval(-600), editedFiles: [],
        folder: URL(filePath: "/Users/preview/Developer/native")
    )

    /// What that turn changed, committed or not, from `base`: the files its agent edited, and one a
    /// command wrote.
    static func turnComparison(
        _ base: GitRangeBase,
        changes: [TreeChange] = [
            TreeChange(path: "README.md", kind: .modified, stats: LineStats(additions: 2)),
            TreeChange(
                path: "native/Git/Views/GitRangeChangesView.swift", kind: .added, stats: LineStats(additions: 214)),
            TreeChange(
                path: "native/Git/Generated/Strings.swift", kind: .modified,
                stats: LineStats(additions: 3, deletions: 1)),
        ]
    ) -> GitRangeComparison {
        GitRangeComparison(
            request: .turn(turn), base: base, baseID: "4f2c9e1a", target: "9e8d7c6b", changes: changes,
            editedPaths: ["README.md", "native/Git/Views/GitRangeChangesView.swift"])
    }

    /// Everything a task branch changed since it left origin/main.
    static let branchComparison = GitRangeComparison(
        request: .branch, base: .branch(BranchBase(commit: "1a2b3c4d", name: "origin/main")), baseID: "1a2b3c4d",
        target: "9e8d7c6b",
        changes: [
            TreeChange(path: "README.md", kind: .modified, stats: LineStats(additions: 2)),
            TreeChange(path: "docs/old-notes.md", kind: .deleted, stats: LineStats(deletions: 42)),
            TreeChange(
                path: "native/Git/Views/GitBranchBadge.swift", originalPath: "native/Git/BranchBadge.swift",
                kind: .renamed, stats: LineStats(additions: 2, deletions: 2)),
        ], editedPaths: [])

    static let commitGroups: [CommitPlan.Group] = [
        CommitPlan.Group(
            message: "feat(git): add GitStore\n\nOne model per working tree, loaded on demand.",
            paths: ["native/Git/Model/GitStore.swift", "Packages/Git/Sources/Git/Git.swift"]),
        CommitPlan.Group(
            message: "refactor(git): move the branch badge into Views",
            paths: ["native/Git/Views/GitBranchBadge.swift", "native/Views/SessionView.swift"]),
    ]
}
#endif
