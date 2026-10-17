import Foundation
import Git
import Observation

/// A smart commit being reviewed: the proposed commits, which the user can rename, reorder, merge
/// and split, and the files left out. Nothing is committed until `commit()`.
@Observable
final class GitSmartCommitModel {
    enum Phase: Equatable {
        case drafting
        case ready
        case committing
    }

    let repository: GitRepositoryModel
    /// Every changed file, once each, as the commit form lists them.
    let files: [GitCommitFile]
    private(set) var groups: [CommitPlan.Group] = []
    private(set) var phase = Phase.drafting
    /// Why the plan is simpler than usual, e.g. grouped by folder without Apple Intelligence.
    private(set) var note: String?
    /// A failed commit, shown in the sheet.
    private(set) var failure: GitNotice?

    init(repository: GitRepositoryModel) {
        self.repository = repository
        files = GitCommitFile.files(from: repository.changes)
    }

    /// Files in no commit; they stay uncommitted.
    var excluded: [GitCommitFile] {
        let included = Set(groups.flatMap(\.paths))
        return files.filter { !included.contains($0.path) }
    }

    func file(_ path: String) -> GitCommitFile? {
        files.first { $0.path == path }
    }

    var canCommit: Bool {
        phase == .ready && !groups.isEmpty
            && groups.allSatisfy { !$0.subject.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    // MARK: - Drafting

    func draft() async {
        phase = .drafting
        failure = nil
        let paths = files.map(\.path)
        do {
            guard let source = repository.repository else { throw GitError.unexpectedOutput("The repository isn't loaded.") }
            async let patch = source.patch(for: repository.changes)
            async let subjects = source.recentCommitSubjects()
            let style = CommitStyle(subjects: try await subjects)
            let plan = try await SmartCommitPlanner().plan(files: files, patch: try await patch, style: style)
            groups = plan.groups
            note =
                SmartCommitPlanner.isAvailable ? nil : "Apple Intelligence isn't available on this Mac, so changes are grouped by folder."
        } catch {
            groups = SmartCommitPlanner.fallback(paths).groups
            note = "Couldn't draft a plan (\(error.localizedDescription)), so changes are grouped by folder."
        }
        phase = .ready
    }

    // MARK: - Editing

    func setSubject(_ subject: String, of id: CommitPlan.Group.ID) {
        update(id) { $0.subject = subject }
    }

    func setBody(_ body: String, of id: CommitPlan.Group.ID) {
        update(id) { $0.body = body }
    }

    /// Moves a file into a commit, or into a new commit at the end when `id` is `nil`.
    func move(_ path: String, to id: CommitPlan.Group.ID?) {
        removeFromGroups(path)
        if let id, groups.contains(where: { $0.id == id }) {
            update(id) { $0.paths.append(path) }
        } else {
            groups.append(CommitPlan.Group(message: "Update \(file(path)?.path.split(separator: "/").last ?? "")", paths: [path]))
        }
        dropEmptyGroups()
    }

    /// Leaves a file out of every commit.
    func exclude(_ path: String) {
        removeFromGroups(path)
        dropEmptyGroups()
    }

    /// Folds a commit's files into the one before it, keeping the earlier message.
    func mergeIntoPrevious(_ id: CommitPlan.Group.ID) {
        guard let index = groups.firstIndex(where: { $0.id == id }), index > 0 else { return }
        groups[index - 1].paths += groups[index].paths
        groups.remove(at: index)
    }

    func moveUp(_ id: CommitPlan.Group.ID) {
        guard let index = groups.firstIndex(where: { $0.id == id }), index > 0 else { return }
        groups.swapAt(index, index - 1)
    }

    func moveDown(_ id: CommitPlan.Group.ID) {
        guard let index = groups.firstIndex(where: { $0.id == id }), index < groups.count - 1 else { return }
        groups.swapAt(index, index + 1)
    }

    /// Drops a commit; its files are left out until moved into another.
    func remove(_ id: CommitPlan.Group.ID) {
        groups.removeAll { $0.id == id }
    }

    // MARK: - Committing

    /// Makes the commits. Returns whether all of them were made; on a failure the sheet shows why.
    func commit() async -> Bool {
        phase = .committing
        failure = nil
        let succeeded = await repository.commit(CommitPlan(groups: groups))
        if !succeeded {
            failure = repository.notice
            phase = .ready
        }
        return succeeded
    }

    // MARK: - Helpers

    private func update(_ id: CommitPlan.Group.ID, _ change: (inout CommitPlan.Group) -> Void) {
        guard let index = groups.firstIndex(where: { $0.id == id }) else { return }
        change(&groups[index])
    }

    private func removeFromGroups(_ path: String) {
        for index in groups.indices {
            groups[index].paths.removeAll { $0 == path }
        }
    }

    private func dropEmptyGroups() {
        groups.removeAll { $0.paths.isEmpty }
    }
}

extension CommitPlan.Group {
    /// The message's first line.
    var subject: String {
        get { message.components(separatedBy: "\n\n").first ?? message }
        set { message = body.isEmpty ? newValue : "\(newValue)\n\n\(body)" }
    }

    /// Everything after the subject's blank line.
    var body: String {
        get { message.components(separatedBy: "\n\n").dropFirst().joined(separator: "\n\n") }
        set {
            let body = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            message = body.isEmpty ? subject : "\(subject)\n\n\(newValue)"
        }
    }
}
