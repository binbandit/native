import Foundation
import Git

extension GitNotice {
    /// What a git operation is, in the words a failure message uses.
    enum Operation {
        case stage, unstage, discard, restore, commit, push, pull, initialize

        var failureTitle: String {
            switch self {
            case .stage: "Couldn't stage the changes"
            case .unstage: "Couldn't unstage the changes"
            case .discard: "Couldn't discard the changes"
            case .restore: "Couldn't restore the files"
            case .commit: "Couldn't commit"
            case .push: "Couldn't push"
            case .pull: "Couldn't pull"
            case .initialize: "Couldn't create the repository"
            }
        }
    }

    /// A failure in plain words with the next step, from git's own error.
    init(failure error: any Error, during operation: Operation) {
        guard let error = error as? GitError else {
            self.init(tone: .failure, title: operation.failureTitle, message: error.localizedDescription)
            return
        }
        let output = Self.output(of: error)
        switch error.failure {
        case .pushRejected:
            self.init(
                tone: .failure, title: "The remote has commits you don't have",
                message: "Pull them in, then push again.", detail: output, action: .pull)
        case .divergentBranches:
            self.init(
                tone: .failure, title: "Your branch and the remote have diverged",
                message:
                    "Git needs to know whether to merge or rebase. Set it once with “git config pull.rebase true” (or false to merge), then pull again.",
                detail: output)
        case .remoteRefused:
            self.init(
                tone: .failure, title: "The remote refused the push",
                message:
                    "The branch may be protected, or a server hook rejected it. Its reason is below; pushing to a new branch and opening a pull request usually works.",
                detail: output)
        case .authenticationFailed:
            self.init(
                tone: .failure, title: "Git couldn't sign in to the remote",
                message:
                    "Check the credentials or SSH key git uses for this remote (try the same command in Terminal), then try again.",
                detail: output, action: operation == .pull ? .pull : .push)
        case .networkUnavailable:
            self.init(
                tone: .failure, title: "Couldn't reach the remote",
                message: "Check your connection, then try again. Your commits are safe locally.",
                action: operation == .pull ? .pull : .push)
        case .noRemote:
            self.init(
                tone: .failure, title: "This repository has no remote",
                message: "Add one with “git remote add origin <url>”, or publish the repository to GitHub, then push.")
        case .detachedHead:
            self.init(
                tone: .failure, title: "You're not on a branch",
                message: "HEAD points at a commit. Create or check out a branch to push your work.")
        case .unmergedFiles:
            self.init(
                tone: .failure, title: "Resolve the conflicts first",
                message: "Edit each conflicted file to remove the conflict markers, stage it, then commit.",
                action: .showConflicts)
        case .conflicts:
            self.init(
                tone: .failure, title: "Pulling stopped on conflicts",
                message: "Resolve the conflicted files and stage them, then commit to finish the merge.",
                detail: output, action: .showConflicts)
        case .nothingToCommit:
            self.init(tone: .failure, title: "Nothing to commit", message: "The selected files match the last commit.")
        case .hookFailed:
            self.init(
                tone: .failure, title: "A commit hook stopped the commit",
                message: "Fix what it reports below, then commit again. Your message and selection are kept.",
                detail: output)
        case .repositoryLocked:
            self.init(
                tone: .failure, title: "Another git process is using this repository",
                message: "An agent may be running git right now. Wait for it to finish, then try again.", detail: output
            )
        case .localChangesWouldBeOverwritten:
            self.init(
                tone: .failure, title: "Pulling would overwrite uncommitted changes",
                message: "Commit or discard those changes first, then pull.", detail: output)
        case .other:
            self.init(
                tone: .failure, title: operation.failureTitle, message: error.localizedDescription,
                detail: output == error.localizedDescription ? nil : output)
        }
    }

    private static func output(of error: GitError) -> String? {
        guard case .failed(_, _, let stderr) = error else { return nil }
        let trimmed = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
