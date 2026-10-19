import Foundation
import Testing

@testable import GitHub

/// The merge control's decision, from a page GitHub returned for a pull request whose base has a
/// merge queue (github/docs, captured read-only), varied one field at a time for the other routes:
/// so the button never reads as "merge now" when it queues or waits.
struct PullRequestMergePlanTests {
    let reference = PullRequestReference(owner: "github", name: "docs", number: 46358)

    /// The captured page, with `change` applied to its repository and pull request first.
    func page(_ change: (inout [String: Any], inout [String: Any]) -> Void = { _, _ in }) throws -> PullRequestPage {
        var json = try #require(
            try JSONSerialization.jsonObject(with: Fixtures.data("pr-page-merge-queue")) as? [String: Any])
        var data = try #require(json["data"] as? [String: Any])
        var repository = try #require(data["repository"] as? [String: Any])
        var pullRequest = try #require(repository["pullRequest"] as? [String: Any])
        change(&repository, &pullRequest)
        repository["pullRequest"] = pullRequest
        data["repository"] = repository
        json["data"] = data
        return try #require(
            try PullRequestPage.decode(JSONSerialization.data(withJSONObject: json), reference: reference))
    }

    /// Push access, which the captured viewer doesn't have.
    func writer(_ repository: inout [String: Any]) {
        repository["viewerPermission"] = "WRITE"
    }

    @Test func capturedQueuePageNeedsPushAccess() throws {
        let page = try page()
        #expect(page.isMergeQueueEnabled)
        #expect(page.mergeState == nil)
        let plan = PullRequestMergePlan(page: page)
        #expect(plan.route == .queue)
        #expect(plan.action == nil)
        #expect(plan.blocker == "Merging needs push access to github/docs.")
    }

    @Test func queueOffersMergeWhenReadyNeverAMerge() throws {
        for status in ["BLOCKED", "CLEAN", "UNSTABLE"] {
            let plan = PullRequestMergePlan(
                page: try page { repository, pullRequest in
                    writer(&repository)
                    pullRequest["mergeStateStatus"] = status
                }, method: .squash)
            #expect(plan.action == .enqueue)
            #expect(plan.title == "Merge When Ready")
            #expect(plan.explanation?.contains("Nothing merges right now") == true)
            #expect(plan.methods.isEmpty)
            #expect(plan.adminMerge == nil)
        }
    }

    @Test func queueLetsAnAdminSkipItApart() throws {
        let plan = PullRequestMergePlan(
            page: try page { repository, pullRequest in
                writer(&repository)
                pullRequest["viewerCanMergeAsAdmin"] = true
                pullRequest["mergeQueue"] = ["configuration": ["mergeMethod": "SQUASH"]]
            })
        #expect(plan.action == .enqueue)
        #expect(plan.adminMerge == .squash)
    }

    @Test func queuedSaysWhereAndOffersRemoval() throws {
        let page = try page { repository, pullRequest in
            writer(&repository)
            pullRequest["mergeQueueEntry"] = ["position": 3, "state": "AWAITING_CHECKS"]
        }
        let plan = PullRequestMergePlan(page: page)
        #expect(plan.action == nil)
        #expect(plan.blocker == nil)
        #expect(plan.state == .queued(position: 3, stage: .awaitingChecks))
        #expect(plan.state?.summary == "Checks running in queue · position 3")
        #expect(plan.canDequeue)
        #expect(
            PullRequestMergeState.queued(position: 2, stage: .queued).summary == "Queued · position 2")
    }

    @Test func removalFromTheQueueSaysWhy() throws {
        let plan = PullRequestMergePlan(
            page: try page { repository, pullRequest in
                writer(&repository)
                pullRequest["queueEvents"] = [
                    "nodes": [["__typename": "RemovedFromMergeQueueEvent", "reason": "failed checks"]]
                ]
            })
        #expect(plan.removedFromQueue == "failed checks")
        #expect(plan.action == .enqueue)
    }

    @Test func autoMergeWaitsForRequirements() throws {
        let plan = PullRequestMergePlan(
            page: try page { repository, pullRequest in
                writer(&repository)
                pullRequest["isMergeQueueEnabled"] = false
                pullRequest["viewerCanEnableAutoMerge"] = true
            }, method: .squash)
        #expect(plan.route == .autoMerge)
        #expect(plan.action == .enableAutoMerge(.squash))
        #expect(plan.title == "Merge When Ready")
        #expect(
            plan.explanation
                == "Turns on auto-merge: GitHub will squash and merge it into main once required checks and reviews pass. Nothing merges right now."
        )
    }

    @Test func greenMergesDirectlyAndSaysHow() throws {
        let plan = PullRequestMergePlan(
            page: try page { repository, pullRequest in
                writer(&repository)
                pullRequest["isMergeQueueEnabled"] = false
                pullRequest["mergeStateStatus"] = "CLEAN"
            }, method: .squash)
        #expect(plan.action == .merge(.squash))
        #expect(plan.title == "Squash and Merge into main")
        #expect(plan.explanation == "Squashes its commits into one and merges it into main now.")
        // The repository doesn't allow rebasing, so the choice falls back to its default.
        let fallback = PullRequestMergePlan(
            page: try page { repository, pullRequest in
                writer(&repository)
                pullRequest["isMergeQueueEnabled"] = false
                pullRequest["mergeStateStatus"] = "CLEAN"
            }, method: .rebase)
        #expect(fallback.title == "Merge into main")
    }

    @Test func autoMergeOnOffersCancelling() throws {
        let plan = PullRequestMergePlan(
            page: try page { repository, pullRequest in
                writer(&repository)
                pullRequest["isMergeQueueEnabled"] = false
                pullRequest["autoMergeRequest"] = ["mergeMethod": "MERGE"]
                pullRequest["viewerCanDisableAutoMerge"] = true
            })
        #expect(plan.action == nil)
        #expect(plan.state == .autoMerge(.merge))
        #expect(plan.state?.summary == "Merges when checks pass")
        #expect(plan.canCancelAutoMerge)
    }

    @Test func directOnlyExplainsWhatsMissing() throws {
        let blocked = try page { repository, pullRequest in
            writer(&repository)
            repository["autoMergeAllowed"] = false
            pullRequest["isMergeQueueEnabled"] = false
        }
        let plan = PullRequestMergePlan(page: blocked)
        #expect(plan.route == .direct)
        #expect(plan.action == nil)
        #expect(plan.blocker == "Branch protection blocks this merge: it needs approvals or passing required checks.")
        #expect(plan.adminMerge == nil)

        let admin = PullRequestMergePlan(
            page: try page { repository, pullRequest in
                writer(&repository)
                repository["autoMergeAllowed"] = false
                pullRequest["isMergeQueueEnabled"] = false
                pullRequest["viewerCanMergeAsAdmin"] = true
            })
        #expect(admin.adminMerge == .merge)
    }

    @Test func conflictsDraftsAndUnknownStopIt() throws {
        let conflicted = PullRequestMergePlan(
            page: try page { repository, pullRequest in
                writer(&repository)
                pullRequest["mergeable"] = "CONFLICTING"
            })
        #expect(conflicted.blocker == "This branch has conflicts with main. Resolve them first.")
        let draft = PullRequestMergePlan(
            page: try page { repository, pullRequest in
                writer(&repository)
                pullRequest["isDraft"] = true
            })
        #expect(draft.blocker == "Drafts can't merge. Mark it ready for review on GitHub first.")
        let unknown = PullRequestMergePlan(
            page: try page { repository, pullRequest in
                writer(&repository)
                pullRequest["isMergeQueueEnabled"] = false
                pullRequest["mergeStateStatus"] = "UNKNOWN"
            })
        #expect(unknown.blocker?.hasPrefix("GitHub is still working out") == true)
        let unstable = PullRequestMergePlan(
            page: try page { repository, pullRequest in
                writer(&repository)
                pullRequest["isMergeQueueEnabled"] = false
                pullRequest["mergeStateStatus"] = "UNSTABLE"
            })
        #expect(unstable.action == .merge(.merge))
        #expect(unstable.note != nil)
    }

    @Test func rowsReadTheSameState() throws {
        let json = #"{"mergeQueueEntry": {"position": 1, "state": "LOCKED"}, "autoMergeRequest": null}"#
        let payload = try JSONDecoder().decode(PullRequestMergeState.Payload.self, from: Data(json.utf8))
        #expect(payload.state == .queued(position: 1, stage: .locked))
        #expect(payload.state?.summary == "Merging from queue")
    }
}
