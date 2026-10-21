import Testing

@testable import ACP

@MainActor
struct TranscriptDisclosuresTests {
    @Test func runsRowsAndGroupsStartClosed() {
        let disclosures = TranscriptDisclosures()
        #expect(!disclosures.isRunOpen("run-first"))
        #expect(!disclosures.isOpen("call-first"))
        #expect(!disclosures.isOpen("exploration-first"))
    }

    @Test func eachSessionKeepsItsOwnChoices() {
        let first = TranscriptDisclosures()
        let second = TranscriptDisclosures()
        first.toggleRun("run-first")
        first.toggle("call-first")
        first.toggle("exploration-first")
        first.unfoldedTurns.insert("turn-first")

        // Agents may reuse item ids in different sessions. Visiting another session must not
        // reset the first one's choices or share them with the second one.
        #expect(!second.isRunOpen("run-first"))
        #expect(!second.isOpen("call-first"))
        #expect(!second.isOpen("exploration-first"))
        #expect(second.unfoldedTurns.isEmpty)
        second.toggleRun("run-second")

        #expect(first.isRunOpen("run-first"))
        #expect(first.isOpen("call-first"))
        #expect(first.isOpen("exploration-first"))
        #expect(first.unfoldedTurns == ["turn-first"])
        #expect(!first.isRunOpen("run-second"))

        first.toggleRun("run-first")
        first.toggle("exploration-first")
        #expect(!first.isRunOpen("run-first"))
        #expect(!first.isOpen("exploration-first"))
        #expect(second.isRunOpen("run-second"))
    }

    @Test func approvalsTemporarilyRevealClosedContainers() {
        let disclosures = TranscriptDisclosures()
        #expect(disclosures.isRunOpen("run-first", hasPendingApproval: true))
        #expect(disclosures.isOpen("exploration-first", hasPendingApproval: true))
        #expect(!disclosures.isRunOpen("run-first"))
        #expect(!disclosures.isOpen("exploration-first"))

        disclosures.toggleRun("run-first")
        disclosures.toggle("exploration-first")
        #expect(disclosures.isRunOpen("run-first", hasPendingApproval: true))
        #expect(disclosures.isOpen("exploration-first", hasPendingApproval: true))
        #expect(disclosures.isRunOpen("run-first"))
        #expect(disclosures.isOpen("exploration-first"))

        disclosures.toggleRun("run-first")
        disclosures.toggle("exploration-first")
        #expect(disclosures.isRunOpen("run-first", hasPendingApproval: true))
        #expect(!disclosures.isRunOpen("run-first"))
        #expect(disclosures.isOpen("exploration-first", hasPendingApproval: true))
        #expect(!disclosures.isOpen("exploration-first"))
    }

    @Test func revealingASearchResultOpensOnlyItsRun() {
        let disclosures = TranscriptDisclosures()
        disclosures.openRun("run-result")
        disclosures.openRun("run-result")
        #expect(disclosures.isRunOpen("run-result"))
        #expect(!disclosures.isRunOpen("run-other"))
        disclosures.toggleRun("run-result")
        #expect(!disclosures.isRunOpen("run-result"))
    }
}
