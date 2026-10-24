import ACP
import CodeThemes
import Foundation

/// Takes a snapshot on entry to Settings. It never opens a task, starts an agent or contacts a host.
enum AppearanceSpecimenSource {
    static func load(model: AppModel, git: GitStore?) async -> SpecimenLine {
        let excluded = BuiltInPlugins.search.center.excludedFolders
        let sessions = model.sessions.loadedSessions
            .filter { $0.phase != .prompting && $0.phase != .loading && $0.parentID == nil && $0.origin == .user }
            .sorted {
                ($0.state.turns.last?.endedAt ?? $0.lastActivity ?? .distantPast)
                    > ($1.state.turns.last?.endedAt ?? $1.lastActivity ?? .distantPast)
            }
        var recentLanguages: [CodeLanguage] = []
        var latest: [SpecimenLine.Candidate] = []
        for session in sessions.prefix(20) {
            guard !Task.isCancelled else { return .sample() }
            let project = model.catalog.lookup(session.key).flatMap { model.projects.project($0.project) }
            guard !isExcluded(session.cwd.path, by: excluded),
                !isExcluded(project?.path ?? session.cwd.path, by: excluded)
            else { continue }
            // Only an already available local repository is read. Remote tasks use their captured diffs.
            let repository =
                latest.isEmpty && model.device(of: session.key) == .thisMac
                ? git?.availableLocalRepository(for: session.cwd) : nil
            let diffs = await GitChangesReview.previewDiffs(
                of: session, in: repository, baselines: git?.turnBaselines ?? .shared)
            let languages = diffs.compactMap { CodeLanguage.forPath($0.path) }
            recentLanguages += languages
            guard latest.isEmpty else { continue }
            let name = project?.name ?? session.cwd.lastPathComponent
            latest = await candidates(diffs: diffs, project: name)
        }
        return await choose(candidates: latest, recentLanguages: recentLanguages)
    }

    private static func isExcluded(_ path: String, by excluded: [String]) -> Bool {
        excluded.contains { SessionFolder.contains($0, path) }
    }

    @concurrent private static func candidates(diffs: [ACP.FileDiff], project: String) async -> [SpecimenLine.Candidate]
    {
        diffs.flatMap {
            SpecimenLine.candidates(
                file: URL(filePath: $0.path).lastPathComponent, project: project,
                before: $0.oldText, after: $0.newText)
        }
    }

    @concurrent private static func choose(
        candidates: [SpecimenLine.Candidate], recentLanguages: [CodeLanguage]
    ) async -> SpecimenLine {
        SpecimenLine.choose(from: candidates, recentLanguages: recentLanguages)
    }
}
