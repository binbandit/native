import Testing

@testable import ACP

@MainActor
struct TranscriptDisclosuresTests {
    @Test func rowsAndGroupsStartClosed() {
        let disclosures = TranscriptDisclosures()
        #expect(!disclosures.isOpen("tool-first"))
        #expect(!disclosures.isOpen("group-first"))
    }

    @Test func eachSessionKeepsItsOwnChoices() {
        let first = TranscriptDisclosures()
        let second = TranscriptDisclosures()
        first.toggle("tool-first")
        first.toggle("group-first")
        first.unfoldedTurns.insert("turn-first")

        // Agents may reuse item ids in different sessions. Visiting another session must not
        // reset the first one's choices or share them with the second one.
        #expect(!second.isOpen("tool-first"))
        #expect(!second.isOpen("group-first"))
        #expect(second.unfoldedTurns.isEmpty)
        second.toggle("group-second")

        #expect(first.isOpen("tool-first"))
        #expect(first.isOpen("group-first"))
        #expect(first.unfoldedTurns == ["turn-first"])
        #expect(!first.isOpen("group-second"))

        first.toggle("group-first")
        #expect(!first.isOpen("group-first"))
        #expect(second.isOpen("group-second"))
    }

    @Test func revealingASearchResultOpensOnlyItsGroup() {
        let disclosures = TranscriptDisclosures()
        disclosures.open("group-result")
        disclosures.open("group-result")
        #expect(disclosures.isOpen("group-result"))
        #expect(!disclosures.isOpen("group-other"))
        disclosures.toggle("group-result")
        #expect(!disclosures.isOpen("group-result"))
    }
}
