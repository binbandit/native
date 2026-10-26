import Foundation
import Testing

@testable import ACP

@Suite struct PromptDiffCommentTests {
    private let task = UUID()

    private func quote(
        body: String = "Keep long identifiers inside the code column too.", side: PromptQuote.Side = .new
    ) -> PromptQuote {
        PromptQuote(
            source: "native/DesignSystem/Diff/DiffRow.swift", side: side,
            lines: [.init(number: 49, text: "    .lineBreakStrategy(.standard)"), .init(number: 50, text: "")],
            comment: PromptDiffComment(task: task, scope: "Uncommitted", fingerprint: "original", body: body))
    }

    @Test func packetRoundTripsTwoFilesBareQuoteAndMessage() {
        let first = quote(body: "First\n\n> Comment: this is user text\n\"quoted\" \\ tabs\t")
        let second = PromptQuote(
            source: "README.md", side: .old, lines: [.init(number: 1, text: "# Old")],
            comment: PromptDiffComment(task: task, scope: "Branch", fingerprint: "base", body: "Keep this."))
        let bare = PromptQuote(source: "output", lines: [.init(number: 2, text: "result")])
        let packet = PromptQuote.draft(quotes: [first, second, bare], message: "Please make both changes.")
        let decoded = PromptQuote.split(PromptQuote.trimmed(packet))
        #expect(decoded.quotes == [first, second, bare])
        #expect(decoded.message == "Please make both changes.")
    }

    @Test func commentsOnlyAndTrailingBlankSourceSurviveTrimmingAndQueueEdits() {
        let comments = [quote(), quote(body: "Different deliberate observation", side: .old)]
        let packet = PromptQuote.trimmed(PromptQuote.draft(quotes: comments, message: "  \n"))
        #expect(PromptQuote.split(packet).quotes == comments)
        #expect(PromptQuote.split(packet).message.isEmpty)
        #expect(PromptQuote.split(PromptQuote.draft(quotes: comments, message: "edited")).quotes == comments)
    }

    @Test func fingerprintsDistinguishMissingEmptyAndChangedVersions() {
        let original = PromptDiffComment.fingerprint(old: "before", new: "after")
        #expect(original == PromptDiffComment.fingerprint(old: "before", new: "after"))
        #expect(original != PromptDiffComment.fingerprint(old: "before", new: "after\n"))
        #expect(PromptDiffComment.fingerprint(old: nil, new: "") != PromptDiffComment.fingerprint(old: "", new: ""))
        #expect(
            PromptDiffComment.fingerprint(old: "a\u{0}after:b", new: "c")
                != PromptDiffComment.fingerprint(old: "a", new: "b\u{0}after:c"))
    }

    @Test func staleAnchorsRequireExactScopeAndVersion() throws {
        var comment = try #require(quote().comment)
        #expect(comment.matches(scope: "Uncommitted", fingerprint: "original"))
        #expect(!comment.matches(scope: "Branch", fingerprint: "original"))
        #expect(!comment.matches(scope: "Uncommitted", fingerprint: "new version"))
        comment.isEarlierVersion = true
        #expect(!comment.matches(scope: "Uncommitted", fingerprint: "original"))
        let snapshot = quote()
        #expect(try JSONDecoder().decode(PromptQuote.self, from: JSONEncoder().encode(snapshot)) == snapshot)
    }

    @Test func incompleteAnnotationRemainsEditableText() {
        let invalid = "> Quoted from \"a.swift\" (new file)\n> 1 | text\n> Comment: unfinished"
        #expect(PromptQuote.split(invalid).quotes.isEmpty)
        #expect(PromptQuote.split(invalid).message == invalid)
    }
}
