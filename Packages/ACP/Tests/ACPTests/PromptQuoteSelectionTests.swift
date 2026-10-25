import Testing

@testable import ACP

struct PromptQuoteSelectionTests {
    private let rows: [PromptQuoteSelection.Row] = [
        .init(side: .new, line: .init(number: 44, text: "prompts.remove(at: index)")),
        .init(side: .old, line: .init(number: 44, text: "prompts.append(Prompt(id: id, text: text))")),
        .init(side: .new, line: .init(number: 45, text: "prompts.append(edited)")),
    ]

    @Test func newFileRangeSkipsInterleavedOldLines() {
        let selection = PromptQuoteSelection(source: "PromptQueue.swift", rows: rows, range: 0...2)
        #expect(selection.indices == [0, 2])
        #expect(selection.quotes.count == 1)
        #expect(selection.quotes.first?.side == .new)
        #expect(selection.quotes.first?.lines.map(\.number) == [44, 45])
    }

    @Test func crossingSidesKeepsBothIdentities() {
        let selection = PromptQuoteSelection(source: "PromptQueue.swift", rows: rows, range: 1...2)
        #expect(selection.quotes.map(\.side) == [.old, .new])
        #expect(selection.quotes.map { $0.lines.map(\.number) } == [[44], [45]])
    }

    @Test func gapsAndInvalidRangesNeverInventSourceLines() {
        let gapped = rows + [.init(side: .new, line: nil), .init(side: .new, line: .init(number: 90, text: "end()"))]
        let selection = PromptQuoteSelection(source: "PromptQueue.swift", rows: gapped, range: 0...4)
        #expect(selection.quotes.map { $0.lines.map(\.number) } == [[44, 45], [90]])
        #expect(PromptQuoteSelection(source: "gone", rows: [], range: 0...1).quotes.isEmpty)
    }
}
