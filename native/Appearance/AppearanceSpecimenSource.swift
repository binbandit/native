import ACP
import CodeThemes
import Foundation

/// Takes a snapshot on entry to Settings. It never opens a task, starts an agent or contacts a host.
enum AppearanceSpecimenSource {
    static func load(model: AppModel) async -> SpecimenLine {
        let excluded = BuiltInPlugins.search.center.excludedFolders
        let sessions = model.sessions.loadedSessions
            .filter { $0.phase != .prompting && $0.phase != .loading && $0.parentID == nil && $0.origin == .user }
            .sorted {
                ($0.state.turns.last?.endedAt ?? $0.lastActivity ?? .distantPast)
                    > ($1.state.turns.last?.endedAt ?? $1.lastActivity ?? .distantPast)
            }
        var snapshots: [SpecimenSource.TaskChanges] = []
        for session in sessions.prefix(20) {
            guard !Task.isCancelled else { return .sample() }
            let project = model.catalog.lookup(session.key).flatMap { model.projects.project($0.project) }
            guard !isExcluded(session.cwd.path, by: excluded),
                !isExcluded(project?.path ?? session.cwd.path, by: excluded)
            else { continue }
            snapshots.append(
                .init(
                    project: project?.name ?? session.cwd.lastPathComponent,
                    isFinished: session.phase != .prompting && session.phase != .loading,
                    changes: GitChangesReview.previewDiffs(of: session).map {
                        .init(path: $0.path, before: $0.oldText, after: $0.newText)
                    }))
        }
        return await choose(snapshots)
    }

    private static func isExcluded(_ path: String, by excluded: [String]) -> Bool {
        excluded.contains { SessionFolder.contains($0, path) }
    }

    @concurrent private static func choose(_ snapshots: [SpecimenSource.TaskChanges]) async -> SpecimenLine {
        SpecimenSource.choose(from: snapshots)
    }
}
