import Experiments
import ACP
import TextInput
import SwiftUI
@testable import Native
#Preview("Composer field - Empty, draft, attachments and growing text") {
    ComposerSinglePreview {
        VStack(spacing: DS.Space.lg) {
            ComposerFieldPreviewFixtures.field()
            ComposerFieldPreviewFixtures.field("Keep the message field calm and the controls close together.")
            ComposerFieldPreviewFixtures.field("Review the attached layout and comment.", attachments: true)
            ComposerFieldPreviewFixtures.field(
                (1...12).map { "Line \($0): text grows upward, then scrolls after ten lines." }.joined(separator: "\n"))
        }
    }
}
#Preview("Composer field - Narrow, working and labelled stopping") {
    ComposerSinglePreview {
        VStack(spacing: DS.Space.lg) {
            ComposerFieldPreviewFixtures.field("A narrow new task", width: DS.ComposerField.narrowWidth)
            ComposerFieldPreviewFixtures.field("A follow-up waits in the queue", working: true)
            ComposerFieldPreviewFixtures.field("Keep this draft when stopped", working: true, stopping: true)
        }
    }
}
#Preview("Composer field - File and command lists") {
    ComposerSinglePreview {
        VStack(spacing: DS.Space.lg) {
            ComposerFieldSuggestions(
                items: [
                    .file("./"), .file("native/"), .file("native/Composer/"),
                    .file("native/Composer/ComposerField.swift"),
                ],
                highlighted: .constant(2), choose: { _ in })
            ComposerFieldSuggestions(
                items: [
                    .command(.init(native: "goal", description: "Manage the task goal")),
                    .command(.init(native: "plan", description: "Plan the next change")),
                    .command(.init(native: "compact", description: "Compact the conversation")),
                ],
                highlighted: .constant(0), choose: { _ in })
        }
        .frame(width: DS.ComposerField.completionWidth)
    }
}
#Preview("Composer field - Attachment failure") {
    ComposerSinglePreview {
        VStack(spacing: DS.Space.sm) {
            NoticeBanner(tone: .warning, title: "Couldn't attach Layout.png. Try attaching it with Attach Files.")
            ComposerFieldPreviewFixtures.field("Review the layout once I attach it.")
        }
        .frame(width: DS.ComposerField.previewWidth)
    }
}
#Preview("Composer field - Completion above the caret") {
    ComposerSinglePreview {
        VStack(spacing: 0) {
            Spacer(minLength: ComposerMetrics.suggestionListMaxHeight)
            ComposerField(
                text: .constant("Review @./"), isFocused: .constant(true), openMenu: .constant(nil),
                state: ComposerRowPreviewFixtures.state, actions: .init(),
                files: ["native/", "docs/", "Packages/", "README.md"]
            ) { EmptyView() }
        }
        .frame(width: DS.ComposerField.previewWidth)
    }
}
#Preview("Composer pending - Working queue and stopped queue") {
    ComposerSinglePreview {
        VStack(spacing: DS.Space.lg) {
            ComposerPendingPreviewFixtures.composer(.working)
            ComposerPendingPreviewFixtures.composer(.stopped)
        }
    }
}
#Preview("Composer pending - Question keeps the draft visible") {
    ComposerSinglePreview { ComposerPendingPreviewFixtures.composer(.question) }
}
#Preview("Composer pending - Approval keeps the draft visible") {
    ComposerSinglePreview { ComposerPendingPreviewFixtures.composer(.approval) }
}
#Preview("Composer queue - Mid-turn delivery") {
    ComposerSinglePreview {
        ComposerQueueSection(
            messages: [
                .init(id: UUID(), text: "Check the narrow layout too."),
                .init(id: UUID(), text: "Then run the focused tests.", attachments: ["Layout.png"]),
            ], sendNowHelp: "Add this message to the running turn after its tools finish",
            onSendNow: { _ in }, onRemove: { _ in }
        ).frame(width: DS.ComposerField.previewWidth)
    }
}
#Preview("Composer queue - No mid-turn delivery, long message and files only") {
    ComposerSinglePreview {
        ComposerQueueSection(
            messages: [
                .init(
                    id: UUID(),
                    text: "Check that a long queued message stays on one line and leaves room for its Remove action."),
                .init(id: UUID(), text: "", attachments: ["Layout.png", "ComposerField.swift"]),
            ], onSendNow: { _ in }, onRemove: { _ in }
        ).frame(width: DS.ComposerField.narrowWidth)
    }
}
#Preview("DSMessageInput - Empty and multiline") {
    ComposerSinglePreview {
        VStack(spacing: DS.Space.md) {
            DSMessageInputPreview(text: "")
            DSMessageInputPreview(text: "Keep the draft.\nThen check the changed files.")
        }
    }
}
private struct DSMessageInputPreview: View {
    @State var text: String
    @FocusState private var isFocused: Bool

    var body: some View {
        DSMessageInput(text: $text, placeholder: "Write a message", isFocused: $isFocused, onKey: { _ in false })
            .frame(width: DS.TextInput.previewWidth)
    }
}

#Preview("Composer agent menu - All agents and inline effort") {
    ComposerSinglePreview { ComposerRowPreviewFixtures.agentMenu() }
}
#Preview("Composer mode menu - Four modes") {
    ComposerSinglePreview { ComposerModeMenu(choices: ComposerRowPreviewFixtures.state.modes) { _ in } }
}
#Preview("Composer where menu - Folder or new branch") {
    ComposerSinglePreview { ComposerWhereMenu(choices: ComposerRowPreviewFixtures.state.locations) { _ in } }
}
#Preview("Quick Entry - Selection") {
    ComposerRenderQuickEntry(state: .selection)
}
#Preview("Quick Entry - Empty") {
    ComposerRenderQuickEntry(state: .empty)
}
#Preview("Quick Entry - First launch") {
    ComposerRenderQuickEntry(state: .firstLaunch)
}
#Preview("Quick Entry - Missing folder") {
    ComposerRenderQuickEntry(state: .failure)
}
#Preview("Quick Entry - Unavailable device") {
    ComposerRenderQuickEntry(state: .offline)
}
#Preview("Quick Entry - Narrow and long text") {
    ComposerRenderQuickEntry(state: .narrow)
}
#Preview("Next start - Rest, typed and failure") {
    ComposerRenderHome.startField()
}
#Preview("Ask composer") {
    let center = PullRequestAskPreviewFixtures.center()
    let empty = center.conversation(for: PullRequestPreviewRunner.reference)
    // Another pull request's conversation, so the two don't share a draft.
    let typed = center.conversation(for: PullRequestAskPreviewFixtures.otherReference)
    typed.draft = "Which of these files would you read first, and why?"
    return ComposerSinglePreview {
        VStack(spacing: DS.Space.lg) {
            PullRequestAskComposer(conversation: empty)
            PullRequestAskComposer(conversation: typed)
        }
        .frame(width: PullRequestAskMetrics.panelIdealWidth)
    }
    .environment(center)
}
#Preview("Starting task - Waiting for restart") {
    ComposerSinglePreview {
        StartingTaskPreviewFixture(failed: false)
    }
}
#Preview("Starting task - Restart failed") {
    ComposerSinglePreview {
        StartingTaskPreviewFixture(failed: true)
    }
}

#Preview("Compose - Letter") { ComposerRenderComposeTask(state: "ready") }

#Preview("Compose - Empty") { ComposerRenderComposeTask(state: "empty") }

#Preview("Compose - First launch") { ComposerRenderComposeTask(state: "firstLaunch") }

#Preview("Compose - Offline") { ComposerRenderComposeTask(state: "offline") }

#Preview("Compose - Held") { ComposerRenderComposeTask(state: "held") }

#Preview("Compose - Devices") { ComposerRenderComposeTask(state: "devices") }

#Preview("Compose - Attachments") { ComposerRenderComposeTask(state: "attachments") }

#Preview("Compose - Changed defaults") { ComposerRenderComposeTask(state: "consequences") }

#Preview("Compose - Two agents") { ComposerRenderComposeTask(state: "twoAgents") }

#Preview("Compose - Failure") { ComposerRenderComposeTask(state: "failure") }

#Preview("Compose - Narrow") { ComposerRenderComposeTask(state: "narrow") }

#Preview("Compose - Start fold") { ComposerRenderComposeTask(state: "folding") }

#Preview("Compose - First message") { ComposerRenderComposeTask(state: "message") }

#Preview("Compose - Settled") { ComposerRenderComposeTask(state: "settled") }

#Preview("Next question - Choices") { ComposerRenderHome.page(.question) }

#Preview("Next question - Free text") { ComposerRenderHome.page(.questionText) }

#Preview("Next question - Several questions") { ComposerRenderHome.page(.questions) }

#Preview("Next question - Answer delivery fails") { ComposerRenderHome.page(.questionFailure) }

#Preview("Next question - Narrow") { ComposerRenderHome.page(.question, narrow: true) }

#Preview("Next ask - Question") { ComposerRenderHome.page(.question) }

#Preview("Next ask - Plan") { ComposerRenderHome.page(.plan) }

#Preview("Next ask - Narrow plan") { ComposerRenderHome.page(.plan, narrow: true) }

#Preview("Next ask - Failure") { ComposerRenderHome.page(.failure) }

#Preview("Next ask - Plan without steps") { ComposerRenderHome.page(.planText) }

#Preview("Next ask - Previous plan") { ComposerRenderHome.page(.planRetained) }

#Preview("Next ask - Destructive hold") { ComposerRenderHome.page(.destructive) }

#Preview("Next ask - Unknown command") { ComposerRenderHome.page(.unknown) }

#Preview("Next ask - Plan delivery failure") { ComposerRenderHome.page(.planFailure) }

#Preview("Next ask - Delivery failure") { ComposerRenderHome.page(.approvalFailure) }

#Preview("Peek - Routine approval") { ComposerRenderPeek.view(.routine) }

#Preview("Peek - Destructive approval") { ComposerRenderPeek.view(.destructive) }

#Preview("Peek - Question") { ComposerRenderPeek.view(.question) }

#Preview("Peek - Question, narrow") {
    ComposerRenderPeek.view(.question, width: 360)
}

#Preview("Peek - Confirmation question") { ComposerRenderPeek.view(.confirmation) }

#Preview("Peek - Answer delivery failed") { ComposerRenderPeek.view(.answerFailure) }

#Preview("Peek - Failure") { ComposerRenderPeek.view(.failure) }

#Preview("Peek - Recovering") { ComposerRenderPeek.view(.recovering) }

#Preview("Peek - Plan") { ComposerRenderPeek.view(.plan) }

#Preview("Peek - Finished") { ComposerRenderPeek.view(.finished) }

#Preview("Peek - Resolved") { ComposerRenderPeek.view(.resolved) }

#Preview("Peek - Loading") { ComposerRenderPeek.view(.loading) }

#Preview("Peek - Missing task") { ComposerRenderPeek.view(.missing) }

#Preview("Peek - Long command, narrow") { ComposerRenderPeek.view(.long, width: 360) }

#Preview("Subagent inspector - Well question") {
    let app = AppModel.preview()
    let subagent = SubagentPreviewFixtures.subagents[1]
    let child = SessionModel.preview(in: app, id: subagent.id.rawValue, title: subagent.title)
    let json = #"""
        {"sessionId":"preview-child","mode":"form","message":"Which layout should the helper check?",
         "requestedSchema":{"type":"object","properties":{"layout":{"type":"string","title":"Layout",
         "description":"Which layout should the helper check?","oneOf":[
         {"const":"narrow","title":"Narrow"},{"const":"wide","title":"Wide"}]}}}}
        """#
    if let request = SessionModel.previewDecode(CreateElicitationRequest.self, json) {
        child?.requestQuestion(request, id: .string("well-question"))
    }
    return ComposerSinglePreview {
        SubagentInspector(subagent: subagent, child: child, showsQuestions: true)
            .frame(width: DS.SessionTools.sidePanelIdealWidth, height: DS.TaskWell.panelWidth)
    }
}

#Preview("Subagent inspector") {
    let app = AppModel.preview()
    let subagents = SubagentPreviewFixtures.subagents
    let child = SessionModel.preview(in: app, id: subagents[0].id.rawValue, title: subagents[0].title)
    child?.previewExchange(
        "Find where the composer queues follow-ups and how Send Now reorders them",
        reply:
            "Follow-ups queue in `SessionModel+Turns.swift` (`enqueue`). Send Now steers when the agent can, otherwise it stops the turn and sends next."
    )
    return ComposerSinglePreview {
        HStack(alignment: .top, spacing: DS.Space.xl) {
            SubagentInspector(subagent: subagents[0], child: child)
                .frame(width: 380, height: 420)
            // Before the agent has sent any of the subagent's traffic.
            SubagentInspector(subagent: subagents[1], child: nil)
                .frame(width: 380, height: 420)
        }
    }
}

#Preview("Composer pending - Review draft comments") {
    ComposerSinglePreview { ComposerPendingPreviewFixtures.composer(.comments) }
}

#Preview("Composer - queued edit before and after start") {
    ComposerSinglePreview {
        VStack(spacing: DS.Space.xl) {
            ComposerStatePreviewFixtures.queuedEdit(started: false)
            ComposerStatePreviewFixtures.queuedEdit(started: true)
        }.frame(width: 760)
    }
}

#Preview("Composer - Field rest, typing, loading and unavailable") {
    ComposerSinglePreview {
        VStack {
            ComposerStatePreviewFixtures.field(phase: .idle)
            ComposerStatePreviewFixtures.field(phase: .idle, draft: "Keep the queued message in its place.")
            ComposerStatePreviewFixtures.field(phase: .loading)
            ComposerStatePreviewFixtures.field(phase: .disconnected)
        }.frame(width: DS.ComposerField.previewWidth)
    }
}

#Preview("Composer - Field narrow") {
    ComposerSinglePreview {
        ComposerStatePreviewFixtures.field(phase: .idle)
            .frame(width: DS.ComposerField.narrowWidth)
    }
}

#Preview("Attachments section") {
    let attachments = ComposerPreviewFixtures.attachments
    ComposerSinglePreview {
        VStack(spacing: DS.Space.xl) {
            ComposerSurface {
                ComposerAttachmentsSection(
                    attachments: attachments, pending: [ComposerPendingAttachment(name: "Recording.mov")], missing: [],
                    selected: nil, capabilities: PromptCapabilities(image: true, embeddedContext: true),
                    agentName: "Claude Code", onRemove: { _ in })
            }
            // An agent that takes neither images nor embedded files, with one file gone from disk.
            ComposerSurface {
                ComposerAttachmentsSection(
                    attachments: attachments, pending: [], missing: [attachments[0].id], selected: attachments[2].id,
                    capabilities: PromptCapabilities(), agentName: "Codex", onRemove: { _ in })
            }
        }
        .frame(width: 560)
    }
}

#Preview("Attachment chips") {
    let fixtures = ComposerPreviewFixtures.attachments
    let longName = PromptAttachment(
        url: URL(
            filePath: "/Users/preview/Developer/native/docs/decisions/2026-10-18-queue-follow-ups-while-a-turn-runs.md"),
        content: .text("# Decision\n"), byteCount: 9_200)
    ComposerSinglePreview {
        VStack(alignment: .leading, spacing: DS.Space.md) {
            ForEach(fixtures) { attachment in
                ComposerAttachmentChip(
                    attachment: attachment, pathOnlyReason: nil, isMissing: false, onPreview: {}, onRemove: {})
            }
            ComposerAttachmentChip(
                attachment: fixtures[0], pathOnlyReason: nil, isMissing: false, isSelected: true, onPreview: {},
                onRemove: {})
            ComposerAttachmentChip(
                attachment: fixtures[0], pathOnlyReason: nil, isMissing: true, onPreview: {}, onRemove: {})
            ComposerAttachmentChip(
                attachment: fixtures[1], pathOnlyReason: "Codex can’t take images, so it gets its path instead.",
                isMissing: false, onPreview: {}, onRemove: {})
            ComposerAttachmentChip(
                attachment: longName, pathOnlyReason: nil, isMissing: false, onPreview: {}, onRemove: {})
            ComposerPendingAttachmentChip(pending: ComposerPendingAttachment(name: "Simulator Screenshot.png"))
        }
    }
}

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

#if NATIVE_PREVIEWS_WIP
import Exec
import Foundation
import GitHub

/// Answers the gh commands a pull request page runs with fixture JSON shaped like gh's, so page
/// previews load through the app's own code without gh, a network or a login. Anything else fails
/// as if gh weren't installed, so a preview never writes anywhere.
nonisolated struct PullRequestPreviewRunner: CommandRunner {
    enum Scenario: Sendable {
        /// Someone else's open pull request, under review: threads, a review, failing checks.
        case reviewing
        /// The viewer's own open pull request, ready to merge.
        case own
        /// A merged pull request.
        case merged
        /// gh can't reach GitHub.
        case offline
    }

    var scenario: Scenario = .reviewing

    static let reference = PullRequestReference(owner: "binbandit", name: "native", number: 212)

    func run(_ command: Command) async throws -> CommandResult {
        if scenario == .offline {
            return CommandResult(
                exitCode: 1, standardOutput: Data(),
                standardError: Data("error connecting to api.github.com\ncheck your internet connection".utf8))
        }
        let arguments = command.arguments
        let input = command.standardInput.map { String(decoding: $0, as: UTF8.self) } ?? ""
        let json: String? =
            if arguments.contains("graphql"), input.contains("mergeCommitAllowed") {
                PullRequestPagePreviewFixtures.page(scenario)
            } else if arguments.contains(where: { $0.contains("/pulls/212/files") }) {
                arguments.contains(where: { $0.hasSuffix("page=1") }) ? PullRequestPagePreviewFixtures.patches : "[]"
            } else if arguments.starts(with: ["pr", "checks"]) || arguments.contains("checks") {
                PullRequestPagePreviewFixtures.checks
            } else {
                nil
            }
        guard let json else { throw CommandError.notFound(command.executable) }
        return CommandResult(exitCode: 0, standardOutput: Data(json.utf8), standardError: Data())
    }
}
#endif

#if NATIVE_PREVIEWS_WIP
import Foundation

/// gh's answers for one pull request, binbandit/native#212, in the shapes `PullRequestPreviewRunner`
/// returns: the page query (GraphQL), the files' patches (REST) and `gh pr checks`. Dates are
/// relative to now, so ages read like a real afternoon's work.
nonisolated enum PullRequestPagePreviewFixtures {
    static let author = "binbandit"
    static let reviewer = "preview-reviewer"

    static func page(_ scenario: PullRequestPreviewRunner.Scenario) -> String {
        let isOwn = scenario != .reviewing
        let isMerged = scenario == .merged
        return """
            {"data": {
              "viewer": {"login": "\(isOwn ? author : reviewer)"},
              "repository": {
                "viewerPermission": "\(isOwn ? "ADMIN" : "WRITE")",
                "mergeCommitAllowed": false, "squashMergeAllowed": true, "rebaseMergeAllowed": true,
                "viewerDefaultMergeMethod": "SQUASH", "autoMergeAllowed": true,
                "pullRequest": {
                  "id": "PR_preview212", "number": 212,
                  "title": "feat(composer): queue follow-ups while a turn runs",
                  "body": \(jsonString(body)),
                  "url": "https://github.com/binbandit/native/pull/212",
                  "state": "\(isMerged ? "MERGED" : "OPEN")", "isDraft": false,
                  "author": {"login": "\(author)"},
                  "createdAt": "\(iso(minutesAgo: 60 * 26))", "updatedAt": "\(iso(minutesAgo: 12))",
                  "mergedAt": \(isMerged ? "\"\(iso(minutesAgo: 8))\"" : "null"), "closedAt": \(isMerged ? "\"\(iso(minutesAgo: 8))\"" : "null"),
                  "headRefName": "native/queue-follow-ups", "baseRefName": "main",
                  "headRefOid": "4f2c9e1a7b3d5e6f8091a2b3c4d5e6f708192a3b", "isCrossRepository": false,
                  "reviewDecision": "\(isOwn ? "APPROVED" : "REVIEW_REQUIRED")",
                  "mergeable": "MERGEABLE", "mergeStateStatus": "\(isOwn ? "CLEAN" : "BLOCKED")",
                  "additions": 136, "deletions": 9, "changedFiles": 5,
                  "viewerDidAuthor": \(isOwn), "viewerCanMergeAsAdmin": \(isOwn),
                  "viewerCanClose": \(isOwn && !isMerged), "viewerCanReopen": false,
                  "viewerCanEnableAutoMerge": \(isOwn && !isMerged), "viewerCanDisableAutoMerge": false,
                  "isMergeQueueEnabled": false, "mergeQueue": null, "mergeQueueEntry": null, "autoMergeRequest": null,
                  "queueEvents": {"nodes": []},
                  "labels": {"nodes": [{"name": "composer", "color": "1d76db", "description": "The prompt composer"}]},
                  "reviewRequests": {"nodes": \(isOwn ? "[]" : "[{\"requestedReviewer\": {\"login\": \"\(reviewer)\"}}]")},
                  "latestOpinionatedReviews": {"nodes": \(isOwn ? "[{\"author\": {\"login\": \"\(reviewer)\"}, \"state\": \"APPROVED\", \"submittedAt\": \"\(iso(minutesAgo: 30))\"}]" : "[]")},
                  "commits": {"nodes": [{"commit": {"oid": "4f2c9e1a7b3d5e6f8091a2b3c4d5e6f708192a3b",
                    "statusCheckRollup": {"state": "\(isOwn ? "SUCCESS" : "FAILURE")", "contexts": {
                      "checkRunCountsByState": [{"state": "SUCCESS", "count": \(isOwn ? 8 : 6)}, {"state": "FAILURE", "count": \(isOwn ? 0 : 1)},
                        {"state": "IN_PROGRESS", "count": \(isOwn ? 0 : 1)}, {"state": "SKIPPED", "count": 1}],
                      "statusContextCountsByState": []}}}}]},
                  "reviews": {"nodes": []},
                  "timelineItems": {"totalCount": 7, "pageInfo": {"hasNextPage": false, "endCursor": "Nw"}, "nodes": \(timeline(merged: isMerged))},
                  "reviewThreads": {"totalCount": 2, "nodes": \(threads(viewerCanReply: true))},
                  "files": {"totalCount": 5, "pageInfo": {"hasNextPage": false, "endCursor": "NQ"}, "nodes": [
                    {"path": "native/Views/Composer/Sections/QueuedPromptsSection.swift", "additions": 48, "deletions": 6, "changeType": "MODIFIED", "viewerViewedState": "UNVIEWED"},
                    {"path": "Packages/ACP/Sources/ACP/Prompt/PromptQueue.swift", "additions": 22, "deletions": 3, "changeType": "MODIFIED", "viewerViewedState": "VIEWED"},
                    {"path": "Packages/ACP/Tests/ACPTests/PromptQueueTests.swift", "additions": 64, "deletions": 0, "changeType": "ADDED", "viewerViewedState": "UNVIEWED"},
                    {"path": "docs/keyboard.md", "additions": 2, "deletions": 0, "changeType": "MODIFIED", "viewerViewedState": "UNVIEWED"},
                    {"path": "design/composer/queued.png", "additions": 0, "deletions": 0, "changeType": "ADDED", "viewerViewedState": "UNVIEWED"}
                  ]}
                }
              }
            }}
            """
    }

    static let body = """
        Follow-ups typed while the agent works now wait in a queue above the draft instead of being \
        refused. Each can be sent now (steered into the turn, or sent after stopping it), edited, moved \
        or removed.

        - `PromptQueue` keeps the order and survives a reload
        - ⌥⌘↑ / ⌥⌘↓ move the message open in the editor
        - Agents that can't steer stop the turn first

        Closes #198.
        """

    private static func timeline(merged: Bool) -> String {
        var nodes = [
            """
            {"__typename": "PullRequestCommit", "id": "PURC_1", "commit": {"oid": "9e8d7c6b5a4f3e2d1c0b9a8f7e6d5c4b3a291807", "abbreviatedOid": "9e8d7c6", "messageHeadline": "feat(acp): keep queued prompts in order across reloads", "committedDate": "\(iso(minutesAgo: 60 * 27))", "author": {"name": "Native Preview", "user": {"login": "\(author)"}}}}
            """,
            """
            {"__typename": "LabeledEvent", "id": "LE_1", "actor": {"login": "\(author)"}, "createdAt": "\(iso(minutesAgo: 60 * 26))", "label": {"name": "composer", "color": "1d76db"}}
            """,
            """
            {"__typename": "ReviewRequestedEvent", "id": "RRE_1", "actor": {"login": "\(author)"}, "createdAt": "\(iso(minutesAgo: 60 * 26))", "requestedReviewer": {"login": "\(reviewer)"}}
            """,
            """
            {"__typename": "PullRequestReview", "id": "PRR_1", "author": {"login": "\(reviewer)"}, "state": "COMMENTED", "body": "Reads well. Two questions inline, mostly about what happens when the agent can't steer.", "submittedAt": "\(iso(minutesAgo: 60 * 3))", "createdAt": "\(iso(minutesAgo: 60 * 3))", "url": "https://github.com/binbandit/native/pull/212#pullrequestreview-1", "comments": {"totalCount": 2}}
            """,
            """
            {"__typename": "PullRequestCommit", "id": "PURC_2", "commit": {"oid": "4f2c9e1a7b3d5e6f8091a2b3c4d5e6f708192a3b", "abbreviatedOid": "4f2c9e1", "messageHeadline": "fix(composer): stop the turn before sending when steering isn't offered", "committedDate": "\(iso(minutesAgo: 40))", "author": {"name": "Native Preview", "user": {"login": "\(author)"}}}}
            """,
            """
            {"__typename": "IssueComment", "id": "IC_1", "author": {"login": "\(author)"}, "body": "Pushed a fix for the non-steering case: Send Now stops the turn, then sends. Mind another look?", "createdAt": "\(iso(minutesAgo: 38))", "lastEditedAt": null, "url": "https://github.com/binbandit/native/pull/212#issuecomment-1", "viewerCanUpdate": true, "viewerCanDelete": true}
            """,
        ]
        if merged {
            nodes.append(
                """
                {"__typename": "MergedEvent", "id": "ME_1", "actor": {"login": "\(author)"}, "createdAt": "\(iso(minutesAgo: 8))", "commit": {"abbreviatedOid": "a1b2c3d"}, "mergeRefName": "main"}
                """)
        }
        return "[" + nodes.joined(separator: ",") + "]"
    }

    private static func threads(viewerCanReply: Bool) -> String {
        """
        [
          {"id": "PRRT_1", "isResolved": false, "isOutdated": false, "path": "native/Views/Composer/Sections/QueuedPromptsSection.swift",
           "line": 31, "startLine": null, "originalLine": 31, "originalStartLine": null, "diffSide": "RIGHT", "startDiffSide": null,
           "subjectType": "LINE", "viewerCanResolve": true, "viewerCanUnresolve": false, "viewerCanReply": \(viewerCanReply),
           "resolvedBy": null, "comments": {"nodes": [
             {"id": "PRRC_1", "author": {"login": "\(reviewer)"}, "body": "What does **Clear all** do while one of these is open in the editor? I'd expect it to keep the open one.", "createdAt": "\(iso(minutesAgo: 60 * 3))", "lastEditedAt": null, "url": "https://github.com/binbandit/native/pull/212#discussion_r1", "diffHunk": "@@ -24,6 +28,12 @@ struct QueuedPromptsSection: View {", "state": "SUBMITTED", "viewerCanUpdate": false, "viewerCanDelete": false},
             {"id": "PRRC_2", "author": {"login": "\(author)"}, "body": "Good catch. It clears everything for now; keeping the open one is a nice follow-up.", "createdAt": "\(iso(minutesAgo: 39))", "lastEditedAt": null, "url": "https://github.com/binbandit/native/pull/212#discussion_r2", "diffHunk": "@@ -24,6 +28,12 @@ struct QueuedPromptsSection: View {", "state": "SUBMITTED", "viewerCanUpdate": true, "viewerCanDelete": true}
           ]}},
          {"id": "PRRT_2", "isResolved": true, "isOutdated": false, "path": "Packages/ACP/Sources/ACP/Prompt/PromptQueue.swift",
           "line": 18, "startLine": 16, "originalLine": 18, "originalStartLine": 16, "diffSide": "RIGHT", "startDiffSide": "RIGHT",
           "subjectType": "LINE", "viewerCanResolve": false, "viewerCanUnresolve": true, "viewerCanReply": \(viewerCanReply),
           "resolvedBy": {"login": "\(author)"}, "comments": {"nodes": [
             {"id": "PRRC_3", "author": {"login": "\(reviewer)"}, "body": "```suggestion\\n        guard let index = items.firstIndex(where: { $0.id == id }) else { return }\\n```", "createdAt": "\(iso(minutesAgo: 60 * 3))", "lastEditedAt": null, "url": "https://github.com/binbandit/native/pull/212#discussion_r3", "diffHunk": "@@ -12,6 +12,9 @@ public struct PromptQueue: Equatable, Sendable {", "state": "SUBMITTED", "viewerCanUpdate": false, "viewerCanDelete": false}
           ]}}
        ]
        """
    }

    /// `gh api repos/binbandit/native/pulls/212/files`: patches for four files, and none for the
    /// picture (GitHub sends no patch for binary files).
    static var patches: String {
        let files: [(name: String, status: String, additions: Int, deletions: Int, patch: String?)] = [
            (
                "native/Views/Composer/Sections/QueuedPromptsSection.swift", "modified", 48, 6,
                """
                @@ -24,6 +28,12 @@ struct QueuedPromptsSection: View {
                     var body: some View {
                         VStack(alignment: .leading, spacing: DS.Space.xxs) {
                             HStack {
                -                Text("Queued")
                +                Text("Queued messages")
                                     .foregroundStyle(.dsTextSecondary)
                                 Spacer()
                +                if prompts.count > 1 {
                +                    Button("Clear all") {
                +                        prompts.forEach { onRemove($0.id) }
                +                    }
                +                    .buttonStyle(.plain)
                +                }
                             }
                """
            ),
            (
                "Packages/ACP/Sources/ACP/Prompt/PromptQueue.swift", "modified", 22, 3,
                """
                @@ -12,6 +12,9 @@ public struct PromptQueue: Equatable, Sendable {
                     public mutating func move(_ id: Item.ID, _ direction: Direction) {
                -        let index = items.firstIndex { $0.id == id }!
                +        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
                +        let target = direction == .up ? index - 1 : index + 1
                +        guard items.indices.contains(target) else { return }
                         items.swapAt(index, target)
                     }
                """
            ),
            (
                "Packages/ACP/Tests/ACPTests/PromptQueueTests.swift", "added", 64, 0,
                """
                @@ -0,0 +1,8 @@
                +import Testing
                +@testable import ACP
                +
                +@Suite struct PromptQueueTests {
                +    @Test func movingTheFirstUpDoesNothing() {
                +        var queue = PromptQueue()
                +    }
                +}
                """
            ),
            (
                "docs/keyboard.md", "modified", 2, 0,
                """
                @@ -40,3 +40,5 @@
                 | Send now | ⌘↩ |
                +| Move the queued message up | ⌥⌘↑ |
                +| Move the queued message down | ⌥⌘↓ |
                """
            ),
            ("design/composer/queued.png", "added", 0, 0, nil),
        ]
        let entries = files.map { file in
            """
            {"filename": "\(file.name)", "status": "\(file.status)", "additions": \(file.additions), \
            "deletions": \(file.deletions), "patch": \(file.patch.map(jsonString) ?? "null")}
            """
        }
        return "[" + entries.joined(separator: ",") + "]"
    }

    /// `gh pr checks --json`: one failing, one running, the rest passed or skipped.
    static var checks: String {
        let checks: [(name: String, state: String, bucket: String, workflow: String, minutesAgo: Double?)] = [
            ("test (ACP)", "FAILURE", "fail", "CI", 30),
            ("iOS check", "IN_PROGRESS", "pending", "CI", nil),
            ("build (macos-26)", "SUCCESS", "pass", "CI", 28),
            ("lint", "SUCCESS", "pass", "CI", 33),
            ("Release and Nightly compile", "SUCCESS", "pass", "Check", 25),
            ("size budget", "SKIPPED", "skipping", "Check", 25),
        ]
        let entries = checks.map { check in
            """
            {"name": "\(check.name)", "state": "\(check.state)", "bucket": "\(check.bucket)", \
            "link": "https://github.com/binbandit/native/actions/runs/1", "workflow": "\(check.workflow)", \
            "description": "", "event": "pull_request", "startedAt": "\(iso(minutesAgo: (check.minutesAgo ?? 4) + 3))", \
            "completedAt": \(check.minutesAgo.map { "\"\(iso(minutesAgo: $0))\"" } ?? "\"0001-01-01T00:00:00Z\"")}
            """
        }
        return "[" + entries.joined(separator: ",") + "]"
    }

    private static func iso(minutesAgo: Double) -> String {
        Date.now.addingTimeInterval(-minutesAgo * 60).formatted(.iso8601)
    }

    private static func jsonString(_ text: String) -> String {
        (try? JSONEncoder().encode(text)).map { String(decoding: $0, as: UTF8.self) } ?? "\"\""
    }
}
#endif

// Render one appearance per window so auto-focused fixture editors do not compete.
private struct ComposerSinglePreview<Content: View>: View {
    let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    var body: some View {
        content.padding(DS.Space.xl).background(.dsBackground).fixedSize()
    }
}

struct ComposerRenderQuickEntry: View {
    let state: QuickEntryPreviewFixtures.State

    var body: some View {
        ComposerSinglePreview {
            let model = QuickEntryPreviewFixtures.model(state)
            QuickEntryPanel(model: model, entry: model.quickEntry, branch: "main")
                .frame(width: state == .narrow ? 380 : DS.QuickEntry.width)
                .padding(DS.Space.xl)
        }
    }
}

struct ComposerRenderComposeTask: View {
    let state: String
    var body: some View {
        ComposerSinglePreview {
            let model = ComposeTaskPreviewFixtures.model(state)
            ComposeTaskPage(model: model, compose: model.composeTask, entry: model.quickEntry)
                .environment(model).environment(ComposeTaskPreviewFixtures.automation())
                .frame(width: state == "narrow" ? 480 : 1000, height: 720)
        }
    }
}

private enum ComposerRenderHome {
    static func startField() -> some View {
        ComposerSinglePreview {
            VStack(spacing: DS.Space.xl) {
                ForEach([HomeNextPreviewFixtures.State.busy, .typed, .startFailure], id: \.self) { state in
                    HomeNextFixtureView(state: state, showsPage: false)
                }
            }.environment(SettingsPresentation())
                .frame(width: DS.HomeNext.column + DS.Space.xxl * 2)
        }
    }
    static func page(_ state: HomeNextPreviewFixtures.State, narrow: Bool = false) -> some View {
        let experiments = ExperimentStore(catalog: .native, storage: InMemoryExperimentStorage())
        return ComposerSinglePreview {
            HomeNextFixtureView(state: state)
                .environment(SettingsPresentation()).environment(\.experimentStore, experiments)
                .frame(width: (narrow || state == .narrow) ? DS.Size.popoverWidth : DS.HomeNext.column + DS.Space.xxxl * 2)
        }
    }
}
private enum ComposerRenderPeek {
    static func view(_ state: TaskPeekPreviewFixtures.State, width: CGFloat = DS.Peek.width) -> some View {
        let app = SidebarDesignFixture.makeApp("plan")
        let request = TaskPeekPreviewFixtures.prepare(app, state: state)
        let experiments = ExperimentStore(catalog: .native, storage: InMemoryExperimentStorage())
        return ComposerSinglePreview { TaskPeekView(request: request).frame(width: width) }
            .environment(app).environment(\.experimentStore, experiments)
            .environment(\.approvalPushReach, { _ in ApprovalPreviewFixtures.forceReach })
    }
}
