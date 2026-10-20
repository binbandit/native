import Git
import SessionTools
import SwiftUI

/// Changes as a session tool: "2 files +12 −3" under the title while the task has uncommitted
/// changes, the changes inspector as its pane (beside the conversation by default), and the
/// files-changed card's Review and Commit.
@MainActor
enum SessionChangesTool {
    static func contribution(git: GitStore, gitHub: GitHubModel) -> SessionToolContribution {
        SessionToolContribution(
            spec: SessionToolSpec(id: .changes, places: [.side, .workbench, .fact, .off], defaultPlace: .side),
            title: "Changes", systemImage: "plus.forwardslash.minus",
            fact: { context in
                let repository = git.model(for: context.session.cwd)
                let count = repository.changes.count
                guard count > 0 else { return nil }
                let totals = repository.totals
                return SessionToolFact(
                    text: count == 1 ? "1 file" : "\(count) files",
                    accessory: .diff(added: totals.additions, removed: totals.deletions))
            },
            hasContent: { !git.model(for: $0.session.cwd).changes.isEmpty },
            pane: { context in
                let repository = git.model(for: context.session.cwd)
                return AnyView(
                    GitChangesInspector(
                        model: repository, review: context.state(GitChangesReview.init), session: context.session
                    ) {
                        Task { await GitHubGitWiring.createPullRequest(from: repository, gitHub: gitHub) }
                    })
            },
            transcript: { context in
                SessionTranscriptActions(turnChanges: turnChanges(context, git: git, gitHub: gitHub))
            })
    }

    /// Review opens the latest turn's changes (one file's, from its row); Commit shows only while
    /// there's something to commit.
    private static func turnChanges(
        _ context: SessionToolContext, git: GitStore, gitHub: GitHubModel
    )
        -> TurnChangesActions
    {
        let repository = git.model(for: context.session.cwd)
        let review = context.state(GitChangesReview.init)
        let show = { (file: String?) in
            review.showTurn(of: context.session, file: file)
            context.open(.changes)
        }
        return TurnChangesActions(
            review: { show(nil) },
            commitForm: repository.canCommit
                ? { isPresented in
                    AnyView(
                        GitCommitPopover(
                            model: repository, isPresented: isPresented,
                            onCreatePullRequest: {
                                Task { await GitHubGitWiring.createPullRequest(from: repository, gitHub: gitHub) }
                            }))
                } : nil,
            reviewFile: { show($0) }
        )
    }
}
