import Testing

@testable import ACP

@Suite struct PromptDiffCommentSelectionTests {
    @Test func rangesKeepOneSideAndBlankContext() {
        let rows: [PromptDiffCommentSelection.Row] = [
            .init(before: .init(number: 48, text: "old"), after: nil),
            .init(before: nil, after: .init(number: 48, text: "new")),
            .init(before: nil, after: .init(number: 49, text: "")),
            .init(before: .init(number: 49, text: "context"), after: .init(number: 50, text: "context")),
        ]
        let before = PromptDiffCommentSelection.quote(source: "a", rows: rows, range: 0...3, side: .old)
        let after = PromptDiffCommentSelection.quote(source: "a", rows: rows, range: 0...3, side: .new)
        #expect(before?.lines.map(\.text) == ["old", "context"])
        #expect(after?.lines.map(\.text) == ["new", "", "context"])
        #expect(before?.side == .old)
    }

    @Test func gapsAndNoncontiguousNumbersNeverAnchorAComment() {
        let rows: [PromptDiffCommentSelection.Row] = [
            .init(before: nil, after: .init(number: 1, text: "a")),
            .init(before: nil, after: nil),
            .init(before: nil, after: .init(number: 10, text: "b")),
        ]
        #expect(PromptDiffCommentSelection.quote(source: "a", rows: rows, range: 0...2, side: .new) == nil)
        #expect(PromptDiffCommentSelection.quote(source: "a", rows: rows, range: 0...9, side: .new) == nil)
        #expect(
            PromptDiffCommentSelection.quote(source: "a", rows: [rows[0], rows[2]], range: 0...1, side: .new) == nil)
    }
    @Test func arrowsCrossHunksButRangeExtensionStopsAtTheGap() {
        let rows: [PromptDiffCommentSelection.Row] = [
            .init(before: .init(number: 5, text: "first"), after: .init(number: 5, text: "first")),
            .init(before: nil, after: nil),
            .init(before: .init(number: 87, text: "second"), after: .init(number: 87, text: "second")),
        ]
        #expect(PromptDiffCommentSelection.nextIndex(in: rows, from: 0, step: 1, side: .new, extending: false) == 2)
        #expect(PromptDiffCommentSelection.nextIndex(in: rows, from: 2, step: -1, side: .new, extending: false) == 0)
        #expect(PromptDiffCommentSelection.nextIndex(in: rows, from: 0, step: 1, side: .new, extending: true) == nil)
        #expect(PromptDiffCommentSelection.nextIndex(in: rows, from: 0, step: 0, side: .old, extending: false) == 0)
        #expect(PromptDiffCommentSelection.nextIndex(in: rows, from: 0, step: 3, side: .new, extending: false) == nil)
    }

    @Test func arrowNavigationSkipsTheOtherSideAndNeverLeavesTheFile() {
        let rows: [PromptDiffCommentSelection.Row] = [
            .init(before: .init(number: 1, text: "old"), after: nil),
            .init(before: nil, after: .init(number: 1, text: "new")),
            .init(before: .init(number: 2, text: "context"), after: .init(number: 2, text: "context")),
        ]
        #expect(PromptDiffCommentSelection.nextIndex(in: rows, from: 0, step: 1, side: .old, extending: true) == 2)
        #expect(PromptDiffCommentSelection.nextIndex(in: rows, from: 2, step: 1, side: .new, extending: false) == nil)
        #expect(PromptDiffCommentSelection.nextIndex(in: rows, from: 1, step: 0, side: .old, extending: false) == nil)
    }

}
