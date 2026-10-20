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
