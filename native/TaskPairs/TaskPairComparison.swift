import ACP
import Foundation
import Git
import Observation

/// What each task of a pair changed since the commit both started from, committed or not, read
/// from their worktrees. The outcome card counts it; Compare shows it file by file.
@Observable
final class TaskPairComparison {
    struct Version: Identifiable {
        let task: SessionKey
        let agent: String
        /// The branch's last component ("offline-time-2"), or nil when detached.
        let branch: String?
        /// The worktree now, as a snapshot's tree.
        let target: String
        let changes: [TreeChange]
        /// Reads one of `changes` against the base, in full past the size diffs collapse at.
        let diff: @MainActor (TreeChange, _ inFull: Bool) async -> GitDiffContent?

        var id: SessionKey { task }
        var totals: LineStats { changes.compactMap(\.stats).reduce(.zero, +) }

        func change(at path: String) -> TreeChange? {
            changes.first { $0.path == path }
        }
    }

    enum State {
        case loading
        case ready(base: String, versions: [Version])
        case failed(String)
    }

    private(set) var state = State.loading
    /// Frozen for a preview: it never runs git.
    @ObservationIgnored private var isFixed = false

    init() {}

    #if DEBUG
    init(fixed state: State) {
        self.state = state
        isFixed = true
    }
    #endif

    var versions: [Version] {
        if case .ready(_, let versions) = state { versions } else { [] }
    }

    func version(_ key: SessionKey) -> Version? {
        versions.first { $0.task == key }
    }

    /// Every file either version changed, in path order.
    var paths: [String] {
        Set(versions.flatMap { $0.changes.map(\.path) })
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    /// Reads both worktrees again. What's on screen stays until the new reading replaces it.
    func load(_ pair: TaskPair, model: AppModel, git: GitStore) async {
        guard !isFixed else { return }
        do {
            let loaded = try await Self.read(pair, model: model, git: git)
            guard !Task.isCancelled else { return }
            state = .ready(base: loaded.base, versions: loaded.versions)
        } catch {
            guard !Task.isCancelled else { return }
            if case .ready = state { return }
            state = .failed(error.localizedDescription)
        }
    }

    private static func read(
        _ pair: TaskPair, model: AppModel, git: GitStore
    ) async throws -> (base: String, versions: [Version]) {
        var sides: [(key: SessionKey, branch: String?, head: String, target: String, repository: Repository)] = []
        for key in pair.tasks {
            let agent = model.taskPairAgentName(key)
            guard
                let folder = model.session(key)?.cwd
                    ?? model.catalog.lookup(key).map({ URL(filePath: $0.info.cwd, directoryHint: .isDirectory) })
            else { throw Failure("\(agent)'s task isn't listed any more.") }
            let checkout = git.model(for: folder, session: key)
            if checkout.repository == nil { await checkout.refreshNow() }
            guard let repository = checkout.repository else { throw Failure("Couldn't read \(agent)'s worktree.") }
            guard let head = try await repository.headCommit() else {
                throw Failure("\(agent)'s worktree has no commits to compare.")
            }
            let branch: String? =
                if case .branch(let name)? = checkout.branch?.head {
                    name.split(separator: "/").last.map(String.init)
                } else { nil }
            sides.append((key, branch, head, try await repository.snapshot().tree, repository))
        }
        // The commit both worktrees were made from; for a pair started without one, where their
        // histories meet.
        guard sides.count == 2, let first = sides.first, let last = sides.last else {
            throw Failure("These two versions can't be compared.")
        }
        let base: String?
        if let start = pair.start, try await first.repository.hasObject(start) {
            base = start
        } else {
            base = try await first.repository.mergeBase(first.head, last.head)
        }
        guard let base else {
            throw Failure("These two versions don't start from the same commit, so they can't be compared.")
        }
        var versions: [Version] = []
        for side in sides {
            let (repository, target) = (side.repository, side.target)
            versions.append(
                Version(
                    task: side.key, agent: model.taskPairAgentName(side.key), branch: side.branch, target: target,
                    changes: try await repository.treeChanges(from: base, to: target),
                    diff: { change, inFull in
                        await GitDiffContent.load(
                            change, between: base, and: target, in: repository, expanded: inFull)?.content
                    }))
        }
        return (base, versions)
    }

    private struct Failure: LocalizedError {
        let message: String
        init(_ message: String) { self.message = message }
        var errorDescription: String? { message }
    }
}
