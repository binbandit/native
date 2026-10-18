import Testing

@testable import ACP

struct DraftBackspaceTests {
    @Test func firstPressInAnEmptyDraftTakesOffTheLastFile() {
        #expect(
            DraftBackspace(isDraftEmpty: true, isComposing: false, hasAttachments: true, isRepeat: false)
                == .removeLastAttachment)
    }

    /// Holding Backspace to clear the text mustn't carry on into the files.
    @Test func aHeldKeyStopsAtTheFiles() {
        #expect(
            DraftBackspace(isDraftEmpty: true, isComposing: false, hasAttachments: true, isRepeat: true) == .swallow)
    }

    @Test func textAndInputMethodsKeepTheKey() {
        // The key deletes the last character; the draft is only empty after that.
        #expect(DraftBackspace(isDraftEmpty: false, isComposing: false, hasAttachments: true, isRepeat: false) == nil)
        // Marked text (Japanese, Chinese input) is edited by Backspace while the draft still reads empty.
        #expect(DraftBackspace(isDraftEmpty: true, isComposing: true, hasAttachments: true, isRepeat: false) == nil)
        #expect(DraftBackspace(isDraftEmpty: true, isComposing: false, hasAttachments: false, isRepeat: false) == nil)
    }
}
