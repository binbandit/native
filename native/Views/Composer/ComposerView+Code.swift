import ACP
import SwiftUI

// Code in the draft: in a fenced block, Return makes a new line and Tab indents (`PromptCode`), and
// the hint says how to send instead. The editor sets code apart itself (`ComposerEditor`).
extension ComposerView {
    /// The selection in the draft, when the editor has reported one that still fits it.
    var selectedRange: Range<String.Index>? {
        guard case .selection(let range)? = selection?.indices, range.upperBound <= draftText.endIndex else {
            return nil
        }
        return range
    }

    /// Whether the caret is in a fenced code block.
    var isCaretInCodeBlock: Bool {
        selectedRange.map { PromptCode.isInBlock($0.upperBound, in: draftText) } ?? false
    }

    /// The hint in a code block: Return's new line, and what ⌘Return does instead, which is what
    /// Return does elsewhere.
    var codeBlockHint: FollowUpHint {
        if session.editingQueuedPrompt != nil {
            return .inCodeBlock(primary: "Save", explanation: "Save the edit, keeping its place in the queue.")
        }
        guard isWorking else { return .inCodeBlock(primary: "Send", explanation: "Send the message.") }
        let behavior = session.supportsSteering ? followUp : .queue
        return .inCodeBlock(primary: behavior.title, explanation: behavior.explanation)
    }

    /// Applies a code edit to the draft at the selection, and selects what it says.
    func editCode(_ edit: (String, Range<String.Index>) -> PromptCode.Edit) {
        guard let range = selectedRange else { return }
        let result = edit(draftText, range)
        draftText = result.text
        selection =
            result.selection.isEmpty
            ? TextSelection(insertionPoint: result.selection.lowerBound) : TextSelection(range: result.selection)
    }
}
