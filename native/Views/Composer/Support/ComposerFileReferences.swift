import ACP
import Git
import SwiftUI

struct ComposerFileReferenceWiring: ViewModifier {
    let session: SessionModel
    @Environment(GitStore.self) private var git
    @State private var reported: [String: FileReferenceProjection.Counts] = [:]
    @Experiment(.composerNext) private var composerNext

    func body(content: Content) -> some View {
        content.environment(\.composerFileReferenceCounts, fileReferenceCounts)
            .onChange(of: session.completedWriteCount, initial: true) { refreshReportedCounts() }
            .onChange(of: session.phase) { refreshReportedCounts() }
            .onChange(of: session.lastActivity) { refreshReportedCounts() }
            .onChange(of: composerNext) { refreshReportedCounts() }
    }

    /// Reuses the repository monitor. A committed edit can still have reported turn counts; an
    /// unknown/binary file has no numeric claim. Absolute agent paths are matched against this task.
    private var fileReferenceCounts: [String: FileReferenceProjection.Counts] {
        guard composerNext else { return [:] }
        var result = reported
        let root = session.cwd.standardizedFileURL.path(percentEncoded: false) + "/"
        let repository = git.model(for: session.cwd, session: session.key)
        let repositoryRoot =
            (repository.repository?.root ?? session.cwd).standardizedFileURL.path(percentEncoded: false) + "/"
        let changes = repository.status?.changes ?? []
        for path in Set(changes.map(\.path)) {
            let absolute = repositoryRoot + path
            let mention = absolute.hasPrefix(root) ? String(absolute.dropFirst(root.count)) : absolute
            let matching = changes.filter { $0.path == path }
            guard matching.allSatisfy({ $0.stats != nil && $0.stats?.isBinary == false }) else {
                result[mention] = nil; result[absolute] = nil
                continue
            }
            let added = matching.reduce(0) { $0 + ($1.stats?.additions ?? 0) }
            let removed = matching.reduce(0) { $0 + ($1.stats?.deletions ?? 0) }
            result[mention] = .init(added: added, removed: removed)
            result[absolute] = result[mention]
        }
        return result
    }
    private func refreshReportedCounts() {
        guard composerNext else { reported = [:]; return }
        let root = session.cwd.standardizedFileURL.path(percentEncoded: false) + "/"
        var result: [String: FileReferenceProjection.Counts] = [:]
        if let turn = session.state.turns.last {
            for file in session.state.summary(of: turn).changedFiles {
                let path = file.path.hasPrefix(root) ? String(file.path.dropFirst(root.count)) : file.path
                result[path] = .init(added: file.added, removed: file.removed)
                result[file.path] = result[path]
            }
        }
        if reported != result { reported = result }
    }

}

extension EnvironmentValues {
    @Entry var composerFileReferenceCounts: [String: FileReferenceProjection.Counts] = [:]
}
