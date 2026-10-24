import ACP
import Foundation
import Git

extension GitChangesReview {
    /// A bounded copy of the latest turn's changes without selecting files or moving its inspector.
    /// Captured edit diffs also work offline, before a repository has been opened on this client.
    static func previewDiffs(
        of session: SessionModel, in repository: Repository?, baselines: GitTurnBaselines
    ) async -> [FileDiff] {
        guard session.phase != .prompting, !session.isRestoringHistory,
            let turn = session.state.turns.last, !turn.isLateOutput
        else { return [] }
        let captured = session.state.items[turn.items].reversed().flatMap { item -> [FileDiff] in
            guard case .toolCall(let call) = item, call.status == .completed else { return [] }
            return call.content.compactMap { if case .diff(let diff) = $0 { diff } else { nil } }
        }
        guard let startedAt = turn.startedAt, let repository,
            let baseline = baselines.baseline(of: session.key, startedAt: startedAt),
            baseline.root == repository.root.path(percentEncoded: false),
            (try? await repository.hasObject(baseline.snapshot.tree)) == true,
            let now = await GitTurnBaselines.snapshot(of: repository),
            let changes = try? await repository.treeChanges(from: baseline.snapshot.tree, to: now.tree)
        else { return Array(captured.prefix(12)) }
        var diffs: [FileDiff] = []
        for change in changes.prefix(12) where !change.isSubmodule {
            guard !Task.isCancelled else { return [] }
            guard let versions = try? await repository.versions(of: change, from: baseline.snapshot.tree, to: now.tree),
                !versions.isBinary, versions.size <= 100_000, let after = versions.newText,
                after.lazy.filter({ $0 == "\n" }).count < 2_000,
                (versions.oldText?.lazy.filter({ $0 == "\n" }).count ?? 0) < 2_000
            else { continue }
            diffs.append(FileDiff(path: change.path, oldText: versions.oldText, newText: after))
        }
        guard session.phase != .prompting, session.state.turns.last == turn else {
            return Array(captured.prefix(12))
        }
        return diffs.isEmpty ? Array(captured.prefix(12)) : diffs
    }
}
