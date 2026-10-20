#if NATIVE_PREVIEWS_WIP
import ACP
import GitHub
import SwiftUI

/// Private questions about binbandit/native#212 for previews: a center that remembers nothing past
/// the preview, and an answered question.
enum PullRequestAskPreviewFixtures {
    /// A center whose records are kept in memory. Views hold conversations' center unowned, so a
    /// preview keeps it alive by putting it in the environment.
    static func center() -> PullRequestAskCenter {
        let center = PullRequestAskCenter()
        center.records = PullRequestAskRecords(defaults: PreviewUserDefaults())
        return center
    }

    /// A second pull request, for a preview showing two conversations.
    static let otherReference = PullRequestReference(owner: "binbandit", name: "native", number: 213)

    static let answer = """
        It queues follow-ups typed while the agent works, instead of refusing them:

        - **What changes:** `QueuedPromptsSection` lists them above the draft, and `PromptQueue` keeps \
        their order across a reload.
        - **What's risky:** Send Now on an agent that can't steer stops the turn first. If the stop \
        takes a while, the message waits, and nothing says so yet.

        I'd test **Clear all** while a queued message is open in the editor; the open thread asks the same.
        """

    /// The turns of a conversation that asked one question and got `answer`.
    static func turns(in app: AppModel) -> [PullRequestAskTurn] {
        guard let session = SessionModel.preview(in: app, id: "ask-212", title: "Ask about #212") else { return [] }
        session.previewExchange("What does this change, and what's risky?", reply: answer, endedAgo: 120)
        return PullRequestAskTurn.turns(of: session)
    }

    static var inclusion: PullRequestAskInclusion {
        var inclusion = PullRequestAskInclusion()
        inclusion.comments = 2
        inclusion.commentsLoaded = 2
        inclusion.threads = 2
        inclusion.threadsLoaded = 2
        inclusion.threadsTotal = 2
        inclusion.files = 5
        inclusion.filesListed = 5
        inclusion.filesInDiff = 5
        inclusion.filesWithPatch = 4
        inclusion.filesWithoutPatch = 1
        inclusion.additions = 136
        inclusion.deletions = 9
        return inclusion
    }

    /// The same pull request, too large to send whole.
    static var partialInclusion: PullRequestAskInclusion {
        var inclusion = Self.inclusion
        inclusion.descriptionTrimmed = true
        inclusion.files = 412
        inclusion.filesListed = 412
        inclusion.filesInDiff = 60
        inclusion.filesWithPatch = 60
        inclusion.additions = 24_800
        inclusion.deletions = 3_100
        return inclusion
    }
}
#endif
