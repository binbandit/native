import Foundation
import Testing

@testable import GitHub

/// The pull request page query against responses captured from GitHub (read-only).
struct ReviewDecodingTests {
    let cli = PullRequestReference(owner: "cli", name: "cli", number: 14569)

    func page(_ fixture: String, _ reference: PullRequestReference) throws -> PullRequestPage {
        try #require(try PullRequestPage.decode(Fixtures.data(fixture), reference: reference))
    }

    @Test func pageWithReviewThreads() throws {
        let page = try page("pr-page-review-threads", cli)

        #expect(page.id.hasPrefix("PR_"))
        #expect(page.state == .merged)
        #expect(page.permission == .read)
        #expect(!page.viewerCanMerge)
        #expect(page.viewerCanApprove)
        #expect(page.reviewDecision == .approved)
        #expect(page.mergeMethods.contains(.squash))
        #expect(page.headRefOid.count == 40)
        #expect(page.checks?.state == .passing)
        #expect(page.checks?.skipped == 27)
        #expect(page.pendingReview == nil)
        #expect(page.threads.count == 14)
        #expect(page.files.count == page.changedFiles)
        #expect(page.files.first?.viewedState == .unviewed)
    }

    @Test func threadsKeepAnchorsAndComments() throws {
        let page = try page("pr-page-review-threads", cli)
        let thread = try #require(page.threads.first)

        #expect(thread.path == "pkg/cmd/issue/artifact/shared/shared.go")
        #expect(thread.isResolved)
        #expect(thread.resolvedBy == "BagToad")
        #expect(thread.anchor == ReviewAnchor(path: thread.path, side: .right, line: 4))
        #expect(thread.comments.count == 2)
        #expect(thread.comments.first?.author == "babakks")
        #expect(thread.comments.first?.diffHunk.hasPrefix("@@") == true)
        #expect(!thread.isPending)
        let range = try #require(page.threads.first { $0.startLine != nil && $0.startLine != $0.line })
        #expect(range.anchor?.startLine == range.startLine)
    }

    @Test func timelineKinds() throws {
        let page = try page("pr-page-review-threads", cli)
        let kinds = Set(
            page.timeline.map { item -> String in
                switch item {
                case .comment: "comment"
                case .review: "review"
                case .commit: "commit"
                case .event(let event):
                    switch event.kind {
                    case .merged: "merged"
                    case .reviewRequested: "requested"
                    case .renamed: "renamed"
                    case .closed: "closed"
                    default: "event"
                    }
                case .other: "other"
                }
            })
        #expect(kinds.isSuperset(of: ["review", "commit", "merged", "requested", "renamed", "closed"]))
        #expect(!kinds.contains("other"))
        guard
            case .commit(let commit) = page.timeline.first(where: {
                if case .commit = $0 { true } else { false }
            })
        else {
            Issue.record("No commit in the timeline")
            return
        }
        #expect(commit.abbreviatedOid == "64da12d")
        #expect(commit.author == "BagToad")
        // A deleted reviewer comes back as null.
        let requested = page.timeline.compactMap { item -> PullRequestTimelineItem.Event? in
            if case .event(let event) = item, case .reviewRequested = event.kind { return event }
            return nil
        }
        #expect(requested.contains { $0.kind == .reviewRequested(nil) })
    }

    @Test func readOnlyViewerWithComments() throws {
        let page = try page(
            "pr-page-read-only", PullRequestReference(owner: "maximhq", name: "bifrost", number: 2584))
        #expect(page.permission == .read)
        #expect(page.viewerDidAuthor)
        #expect(!page.viewerCanApprove)
        #expect(page.timeline.contains { if case .comment = $0 { true } else { false } })
        #expect(page.reviewDecision == .reviewRequired)
    }

    @Test func ownRepository() throws {
        let page = try page(
            "pr-page-own", PullRequestReference(owner: "binbandit", name: "oh-fx", number: 974))
        #expect(page.permission == .admin)
        #expect(page.viewerCanMerge)
        #expect(page.mergeStatus == .blocked)
        #expect(page.filesCursor == nil)
        #expect(page.files.count == 41)
    }

    @Test func missingPullRequestDecodesAsNil() throws {
        let json = #"{"data":{"viewer":{"login":"someone"},"repository":{"pullRequest":null}}}"#
        #expect(try PullRequestPage.decode(Data(json.utf8), reference: cli) == nil)
    }

    @Test func patchesFromREST() throws {
        let patches = try Fixtures.decode([FilePatch].self, from: "pr-files")
        let file = try #require(patches.first { $0.path == "pkg/cmd/issue/artifact/shared/shared.go" })
        #expect(file.status == "modified")
        #expect(file.missingPatchReason == nil)
        let hunk = try #require(file.hunks.first)
        #expect(hunk.oldStart == 1)
        #expect(hunk.newStart == 1)
        // The thread above is on head line 4 of this file.
        #expect(hunk.index(side: .right, line: 4) != nil)
    }
}
