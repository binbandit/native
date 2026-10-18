import Testing

@testable import ACP

struct DraftAttachmentKeysTests {
    typealias Keys = DraftAttachmentKeys
    typealias Outcome = DraftAttachmentKeys.Outcome

    private let empty = Keys.Draft(isEmpty: true, isCaretAtStart: true)
    private let typedAtStart = Keys.Draft(isEmpty: false, isCaretAtStart: true)
    private let typedAtEnd = Keys.Draft(isEmpty: false, isCaretAtStart: false)

    private func outcome(
        _ key: Keys.Key, selection: Int? = nil, count: Int = 3, draft: Keys.Draft? = nil, isRepeat: Bool = false
    ) -> Outcome {
        Keys.outcome(for: key, selection: selection, count: count, draft: draft ?? empty, isRepeat: isRepeat)
    }

    @Test func leftAtTheStartOfTheTextSelectsTheLastChip() {
        #expect(outcome(.left, draft: typedAtStart) == Outcome(selection: 2, passesKey: false))
        #expect(outcome(.left, draft: typedAtEnd) == Outcome(selection: nil, passesKey: true))
        // Holding ← through the text stops at its start.
        #expect(outcome(.left, draft: typedAtStart, isRepeat: true) == Outcome(selection: nil, passesKey: true))
    }

    @Test func arrowsWalkTheChipsAndRightLeavesThemPastTheLast() {
        #expect(outcome(.left, selection: 2) == Outcome(selection: 1, passesKey: false))
        #expect(outcome(.left, selection: 0) == Outcome(selection: 0, passesKey: false))
        #expect(outcome(.right, selection: 1) == Outcome(selection: 2, passesKey: false))
        #expect(outcome(.right, selection: 2) == Outcome(selection: nil, passesKey: false))
    }

    @Test func deleteTakesOffTheSelectedChipAndMovesOn() {
        // Backspace walks left; at the first chip, the new first chip is selected.
        #expect(outcome(.backspace, selection: 2) == Outcome(removing: 2, selection: 1, passesKey: false))
        #expect(outcome(.backspace, selection: 0) == Outcome(removing: 0, selection: 0, passesKey: false))
        // Forward Delete selects the chip that takes its place, or the one before at the end.
        #expect(outcome(.forwardDelete, selection: 0) == Outcome(removing: 0, selection: 0, passesKey: false))
        #expect(outcome(.forwardDelete, selection: 2) == Outcome(removing: 2, selection: 1, passesKey: false))
        // The last chip gone, the caret is back in the text.
        #expect(outcome(.backspace, selection: 0, count: 1) == Outcome(removing: 0, selection: nil, passesKey: false))
        // A held key never removes one.
        #expect(outcome(.backspace, selection: 1, isRepeat: true) == Outcome(selection: 1, passesKey: false))
    }

    @Test func escapeAndTypingReturnToTheText() {
        #expect(outcome(.escape, selection: 1) == Outcome(selection: nil, passesKey: false))
        // The typed key still reaches the text.
        #expect(outcome(.other, selection: 1) == Outcome(selection: nil, passesKey: true))
    }

    @Test func backspaceInAnEmptyDraftTakesOffTheLastChip() {
        #expect(outcome(.backspace) == Outcome(removing: 2, selection: nil, passesKey: false))
        // Holding Backspace to clear the text mustn't carry on into the chips.
        #expect(outcome(.backspace, isRepeat: true) == Outcome(selection: nil, passesKey: false))
        #expect(outcome(.backspace, draft: typedAtStart) == Outcome(selection: nil, passesKey: true))
    }

    /// Japanese or Chinese input edits its composition with these keys while the draft reads empty.
    @Test func inputMethodsKeepEveryKey() {
        let composing = Keys.Draft(isEmpty: true, isCaretAtStart: true, isComposing: true)
        for key: Keys.Key in [.left, .backspace, .escape] {
            #expect(outcome(key, draft: composing) == Outcome(selection: nil, passesKey: true))
        }
    }

    @Test func noChipsMeansNothingToDo() {
        #expect(outcome(.left, count: 0) == Outcome(selection: nil, passesKey: true))
        #expect(outcome(.backspace, selection: 4, count: 0) == Outcome(selection: nil, passesKey: true))
    }
}
