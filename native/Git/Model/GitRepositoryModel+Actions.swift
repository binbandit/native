import Foundation
import Git

/// The git actions the UI offers. Each reports back through `notice`: what happened, what was
/// saved, and what to do next.
extension GitRepositoryModel {
    func stage(_ changes: [FileChange]) async {
        await perform(.stage) { repository in
            try await repository.stage(Self.paths(of: changes))
            return nil
        }
    }

    func unstage(_ changes: [FileChange]) async {
        await perform(.unstage) { repository in
            try await repository.unstage(Self.paths(of: changes))
            return nil
        }
    }

    /// Destructive, so the caller confirms first. A checkpoint is saved before anything is thrown
    /// away, and the notice offers to restore from it.
    func discard(_ changes: [FileChange]) async {
        let paths = Self.paths(of: changes)
        await perform(.discard) { repository in
            let checkpoint = try await repository.discard(changes)
            let files = Set(changes.map(\.path))
            let title = files.count == 1 ? "Discarded changes to \(changes[0].fileName)" : "Discarded changes to \(files.count) files"
            guard let checkpoint else { return GitNotice(tone: .success, title: title) }
            return GitNotice(tone: .success, title: title, message: "A checkpoint was saved first, so you can put them back.", action: .restore(checkpoint, paths: paths))
        }
    }

    func restore(_ checkpoint: Checkpoint, paths: [String]) async {
        await perform(.restore) { repository in
            try await repository.restore(checkpoint, paths: paths)
            return GitNotice(tone: .success, title: paths.count == 1 ? "Restored 1 file" : "Restored \(paths.count) files")
        }
    }

    func push() async {
        let ahead = branch?.ahead ?? 0
        await perform(.push) { repository in
            try await repository.push()
            let upstream = try await repository.status().branch.upstream ?? "the remote"
            return GitNotice(tone: .success, title: ahead == 0 ? "Published to \(upstream)" : ahead == 1 ? "Pushed 1 commit to \(upstream)" : "Pushed \(ahead) commits to \(upstream)")
        }
    }

    func pull() async {
        await perform(.pull) { repository in
            try await repository.pull()
            let upstream = try await repository.status().branch.upstream ?? "the remote"
            return GitNotice(tone: .success, title: "Pulled from \(upstream)")
        }
    }

    /// Commits exactly `files`, staging them and unstaging anything else, then pushes if asked.
    /// A failed commit throws so the commit form can show git's output, often a hook's. A failed
    /// push after a good commit becomes the notice, since the commit itself is saved.
    func commit(message: String, files: [FileChange], push: Bool) async throws {
        try await performThrowing { repository in
            try await repository.commit(message: message, files: files)
            commitMessage = ""
            let subject = message.split(separator: "\n").first.map(String.init) ?? message
            guard push else { return GitNotice(tone: .success, title: "Committed “\(subject)”") }
            do {
                try await repository.push()
            } catch {
                var notice = GitNotice(failure: error, during: .push)
                notice.message = "Your commit is saved locally. " + (notice.message ?? "")
                return notice
            }
            return GitNotice(tone: .success, title: "Committed and pushed “\(subject)”")
        }
    }

    /// A commit message for `files` from the on-device model, in the style of recent commits.
    func draftCommitMessage(for files: [FileChange]) async throws -> String {
        guard let repository else { return "" }
        async let patch = repository.patch(for: files)
        async let subjects = repository.recentCommitSubjects()
        return try await CommitMessageDrafter().draft(patch: patch, files: files, style: CommitStyle(subjects: subjects))
    }

    /// `git init` for a folder that isn't a repository yet.
    func initializeRepository() async {
        do {
            guard let git = try await resolveGit() else { return }
            try await git.initializeRepository(at: folder)
            await refreshNow()
        } catch {
            show(GitNotice(failure: error, during: .initialize))
        }
    }

    /// Takes a notice's offered next step.
    func run(_ action: GitNotice.Action) async {
        switch action {
        case .pull: await pull()
        case .push: await push()
        case .restore(let checkpoint, let paths): await restore(checkpoint, paths: paths)
        case .showConflicts:
            dismissNotice()
            selection = status?.conflicted.first?.id
        }
    }

    /// Every path the changes touch, renames' original paths included.
    static func paths(of changes: [FileChange]) -> [String] {
        Array(Set(changes.flatMap(\.paths))).sorted()
    }
}
