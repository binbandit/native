import Foundation
import Testing
@testable import GitHub

struct CheckSummaryTests {
    @Test func noChecksHasNoSummary() {
        #expect(CheckSummary(outcomes: []) == nil)
    }

    @Test func anyFailureFailsEvenWhileOthersRun() {
        let summary = CheckSummary(outcomes: [.passed, .pending, .failed])
        #expect(summary?.state == .failing)
        #expect(summary?.total == 3)
    }

    @Test func unfinishedChecksKeepItPending() {
        #expect(CheckSummary(outcomes: [.passed, .pending, .skipped])?.state == .pending)
    }

    @Test func skippedChecksDontBlockAPass() {
        let summary = CheckSummary(outcomes: [.passed, .skipped])
        #expect(summary?.state == .passing)
        #expect(summary?.skipped == 1)
    }

    @Test func runningCheckRunIsPendingWhateverItsConclusion() throws {
        let json = #"[{"__typename":"CheckRun","name":"build","status":"IN_PROGRESS","conclusion":"","startedAt":"2026-10-12T06:58:25Z","completedAt":"0001-01-01T00:00:00Z","workflowName":"CI","detailsUrl":""}]"#
        let checks = try GitHubJSON.decode([StatusCheck].self, from: Data(json.utf8))
        let check = try #require(checks.first)

        #expect(check.outcome == .pending)
        #expect(check.conclusion == nil)
        // Go's zero time means it hasn't finished.
        #expect(check.completedAt == nil)
        #expect(check.startedAt != nil)
    }

    @Test func cancelledAndTimedOutRunsFail() {
        #expect(CheckOutcome(state: "CANCELLED") == .failed)
        #expect(CheckOutcome(state: "TIMED_OUT") == .failed)
        #expect(CheckOutcome(state: "neutral") == .skipped)
        #expect(CheckOutcome(state: "EXPECTED") == .pending)
        #expect(CheckOutcome(state: "A_STATE_FROM_THE_FUTURE") == .pending)
    }
}
