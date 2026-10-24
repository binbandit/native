import Foundation
import Testing

@testable import ACP

struct PromptQuoteTests {
    @Test func selectionUsesSourceLinesAndUnicodeOffsets() throws {
        let text = "let emoji = \"👩🏽‍💻\"\n\tfirst()\n\n\tlast()\nend()"
        let selection = try #require(text.range(of: "first()\n\n\tlast"))
        let quote = try #require(PromptQuote(source: "Output", text: text, selection: NSRange(selection, in: text)))
        #expect(quote.lines.map(\.number) == [2, 3, 4])
        #expect(quote.lines.map(\.text) == ["\tfirst()", "", "\tlast()"])
    }

    @Test func newlineAtSelectionEndDoesNotAddNextLine() throws {
        let quote = try #require(
            PromptQuote(
                source: "a.swift", text: "one\ntwo\nthree", selection: NSRange(location: 0, length: 4), firstLine: 44,
                side: .old))
        #expect(quote.lines == [.init(number: 44, text: "one")])
    }

    @Test func draftRoundTripPreservesMultipleSidesAndMessage() {
        let quotes = [
            PromptQuote(source: "a\"b\n.swift", side: .old, lines: [.init(number: 44, text: "\t``` > | text")]),
            PromptQuote(source: "a.swift", side: .new, lines: [.init(number: 45, text: "replacement()")]),
        ]
        let draft = PromptQuote.draft(quotes: quotes, message: "Fix @a.swift\n\nKeep the blank line.")
        let result = PromptQuote.split(draft)
        #expect(result.quotes == quotes)
        #expect(result.message == "Fix @a.swift\n\nKeep the blank line.")
        #expect(PromptQuote.draft(quotes: result.quotes, message: result.message) == draft)
    }

    @Test func displayOutdentsWithoutChangingSentIndentation() {
        let quote = PromptQuote(
            source: "a.swift",
            lines: [
                .init(number: 44, text: "        if ready {"),
                .init(number: 45, text: "            send()"),
                .init(number: 46, text: "        }"),
            ])
        #expect(quote.displayLines.map(\.text) == ["if ready {", "    send()", "}"])
        #expect(quote.prompt.contains("45 |             send()"))
    }

    @Test func quoteOnlySurvivesSubmissionWhitespaceTrimming() {
        let quote = PromptQuote(source: "Output", lines: [.init(number: 2, text: "failure")])
        let sent = quote.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        #expect(PromptQuote.split(sent).quotes == [quote])
        #expect(PromptQuote.split(sent).message.isEmpty)
    }

    @Test func incompleteAndOrdinaryQuotesStayEditable() {
        for text in [
            "> quoted prose", "> Quoted from \"a\" (old file)\n> no numbered line",
            "> Quoted from invalid (transcript)\n\n",
        ] {
            #expect(PromptQuote.split(text).quotes.isEmpty)
            #expect(PromptQuote.split(text).message == text)
        }
    }
}
