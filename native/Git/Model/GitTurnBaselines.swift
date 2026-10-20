import Foundation
import Git
import os

/// Where each task turn began (`GitTurnBaseline`), recorded as the turn starts and kept across
/// launches, so Review can show what a turn changed even after its agent committed it. Snapshots
/// are loose git objects only: no ref, index entry or file the user would see, and git's garbage
/// collection takes them once they're old, when Review falls back as for an unrecorded turn.
@MainActor
final class GitTurnBaselines {
    /// One list for every store (this Mac's and a paired host's), since they share the defaults.
    static let shared = GitTurnBaselines()

    /// A snapshot that takes longer is stopped, so a huge working tree costs a bounded amount of
    /// work; Review then compares with HEAD as it was when the turn began, and says so.
    nonisolated static let snapshotDeadline = Duration.seconds(5)
    /// A working tree with more untracked files than this (an unignored dependency or build folder)
    /// isn't snapshotted: storing them all at every turn would cost more than the review is worth.
    nonisolated static let untrackedLimit = 2000
    /// Turns remembered, across every task; older ones fall back like unrecorded ones.
    static let limit = 200
    private static let defaultsKey = "git.turnBaselines"
    private static let logger = Logger(subsystem: "Native", category: "GitTurnBaselines")

    private let defaults: UserDefaults
    /// Newest last.
    private var baselines: [GitTurnBaseline]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        baselines =
            defaults.data(forKey: Self.defaultsKey).flatMap {
                try? JSONDecoder().decode([GitTurnBaseline].self, from: $0)
            }
            ?? []
    }

    /// The baseline of the turn that began at `startedAt`, if it was recorded.
    func baseline(of session: SessionKey, startedAt: Date) -> GitTurnBaseline? {
        baselines.last { $0.session == session && $0.began(at: startedAt) }
    }

    /// Snapshots `repository` for the turn that began at `startedAt`. Runs after the prompt went
    /// out, never before it: the turn's own edits come seconds later, once the agent has thought.
    func record(_ session: SessionKey, startedAt: Date, in repository: Repository) async {
        guard baseline(of: session, startedAt: startedAt) == nil else { return }
        let start = ContinuousClock.now
        let snapshot = await Self.snapshot(of: repository)
        let elapsed = String(describing: start.duration(to: .now))
        guard let snapshot else {
            Self.logger.notice("Turn snapshot skipped or abandoned after \(elapsed, privacy: .public)")
            return
        }
        Self.logger.info("Turn snapshot took \(elapsed, privacy: .public)")
        let root = repository.root.path(percentEncoded: false)
        baselines.append(GitTurnBaseline(session: session, startedAt: startedAt, root: root, snapshot: snapshot))
        baselines = Array(baselines.suffix(Self.limit))
        if let data = try? JSONEncoder().encode(baselines) {
            defaults.set(data, forKey: Self.defaultsKey)
        }
    }

    /// The snapshot, or nil when git failed, ran past the deadline (and was stopped), or would have
    /// had too many untracked files to store.
    nonisolated private static func snapshot(of repository: Repository) async -> WorkingTreeSnapshot? {
        await withTaskGroup(of: WorkingTreeSnapshot?.self) { group in
            group.addTask {
                guard let untracked = try? await repository.untrackedFileCount(), untracked <= untrackedLimit else {
                    return nil
                }
                return try? await repository.snapshot()
            }
            group.addTask {
                try? await Task.sleep(for: snapshotDeadline)
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }
}
