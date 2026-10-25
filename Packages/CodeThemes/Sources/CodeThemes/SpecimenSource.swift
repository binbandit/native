import Foundation

/// Selects from task-owned snapshots only. There is no repository or file reader in this path.
public enum SpecimenSource {
    public struct Change: Sendable {
        public let path: String
        public let before: String?
        public let after: String

        public init(path: String, before: String?, after: String) {
            self.path = path
            self.before = before
            self.after = after
        }
    }

    public struct TaskChanges: Sendable {
        public let project: String
        public let isFinished: Bool
        public let changes: [Change]

        public init(project: String, isFinished: Bool, changes: [Change]) {
            self.project = project
            self.isFinished = isFinished
            self.changes = changes
        }
    }

    /// Tasks arrive newest first, after the caller has excluded private projects.
    public static func choose(from tasks: [TaskChanges]) -> SpecimenLine {
        var languages: [CodeLanguage] = []
        var latest: [SpecimenLine.Candidate] = []
        for task in tasks.lazy.filter(\.isFinished).prefix(20) {
            for change in task.changes.prefix(12) {
                if let language = CodeLanguage.forPath(change.path) { languages.append(language) }
            }
            guard latest.isEmpty else { continue }
            latest = task.changes.prefix(12).flatMap { change in
                SpecimenLine.candidates(
                    file: URL(filePath: change.path).lastPathComponent, project: task.project,
                    before: change.before, after: change.after)
            }
        }
        return SpecimenLine.choose(from: latest, recentLanguages: languages)
    }
}
