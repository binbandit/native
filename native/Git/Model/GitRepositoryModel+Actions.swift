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
            let title =
                files.count == 1
                ? "Discarded changes to \(changes[0].fileName)" : "Discarded changes to \(files.count) files"
            guard let checkpoint else { return GitNotice(tone: .success, title: title) }
            return GitNotice(
                tone: .success, title: title,
                message: files.count == 1
                    ? "A checkpoint was saved first, so you can put it back."
                    : "A checkpoint was saved first, so you can put them back.",
                action: .restore(checkpoint, paths: paths))
        }
    }

    func restore(_ checkpoint: Checkpoint, paths: [String]) async {
        await perform(.restore) { repository in
            try await repository.restore(checkpoint, paths: paths)
            return GitNotice(
                tone: .success, title: paths.count == 1 ? "Restored 1 file" : "Restored \(paths.count) files")
        }
    }

    func push() async {
        let ahead = branch?.ahead ?? 0
        await perform(.push) { repository in
            try await repository.push()
            await notePushed(repository)
            let upstream = try await repository.status().branch.upstream ?? "the remote"
            return GitNotice(
                tone: .success,
                title: ahead == 0
                    ? "Published to \(upstream)"
                    : ahead == 1 ? "Pushed 1 commit to \(upstream)" : "Pushed \(ahead) commits to \(upstream)")
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
                await notePushed(repository)
            } catch {
                var notice = GitNotice(failure: error, during: .push)
                notice.message = "Your commit is saved locally. " + (notice.message ?? "")
                return notice
            }
            return GitNotice(tone: .success, title: "Committed and pushed “\(subject)”")
        }
    }

    /// Makes a smart commit's commits in order, after a checkpoint, and offers to undo them. When
    /// one fails (often a hook), the ones made so far stay, and the notice says why and still offers
    /// the undo. Returns whether every commit was made.
    @discardableResult
    func commit(_ plan: CommitPlan) async -> Bool {
        var succeeded = false
        await perform(.commit) { repository in
            let (receipt, failure) = try await repository.commit(plan, changes: changes)
            let made = receipt.commits.count == 1 ? "1 commit" : "\(receipt.commits.count) commits"
            guard let failure else {
                succeeded = true
                return GitNotice(tone: .success, title: "Made \(made)", action: .undoCommits(receipt))
            }
            var notice = GitNotice(failure: failure, during: .commit)
            notice.message = "Made \(made) of \(plan.groups.count) before this one failed. " + (notice.message ?? "")
            if !receipt.commits.isEmpty { notice.action = .undoCommits(receipt) }
            return notice
        }
        return succeeded
    }

    /// Takes back a smart commit: the branch and the staged state go back to before it.
    func undoCommits(_ receipt: CommitPlanReceipt) async {
        await perform(.undoCommits) { repository in
            try await repository.undo(receipt)
            return GitNotice(
                tone: .success,
                title: receipt.commits.count == 1 ? "Undid 1 commit" : "Undid \(receipt.commits.count) commits")
        }
    }

    /// A commit message for `files` from the on-device model, in the style of recent commits.
    func draftCommitMessage(for files: [FileChange]) async throws -> String {
        guard let repository else { return "" }
        async let patch = repository.patch(for: files)
        async let subjects = repository.recentCommitSubjects()
        return try await CommitMessageDrafter().draft(
            patch: patch, files: files, style: CommitStyle(subjects: subjects))
    }

    /// `git init` for a folder that isn't a repository yet.
    func initializeRepository() async {
        do {
            guard let git = await resolveGit() else { return }
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
        case .undoCommits(let receipt): await undoCommits(receipt)
        }
    }

    /// Reports a push to `onPushed` with the checkout it ran in.
    private func notePushed(_ repository: Repository) async {
        guard let onPushed, let branch = try? await repository.status().branch.name else { return }
        onPushed(repository.root, branch)
    }

    /// Every path the changes touch, renames' original paths included.
    static func paths(of changes: [FileChange]) -> [String] {
        Array(Set(changes.flatMap(\.paths))).sorted()
    }
}
