import Testing

@testable import ACP

struct FileMentionQueryTests {
    @Test(arguments: ["@", "@./", "@./do", "@docs/", "@../", "@./.config/"])
    func queryKeepsTheTypedPath(draft: String) throws {
        let query = try #require(FileMentionQuery(draft: draft, cursor: draft.endIndex))
        #expect(query.text == String(draft.dropFirst()))
    }

    @Test func choosingAFolderLeavesTheCaretAfterItsSlash() throws {
        let draft = "Look in @./do next"
        let cursor = try #require(draft.dropFirst(8).firstIndex(of: " "))
        let query = try #require(FileMentionQuery(draft: draft, cursor: cursor))
        let result = query.draft(draft, inserting: "docs/")
        #expect(result.text == "Look in @docs/ next")
        #expect(String(result.text[..<result.cursor]) == "Look in @docs/")
        #expect(FileMentionQuery(draft: result.text, cursor: result.cursor)?.text == "docs/")
    }

    @Test func choosingAFileStillAddsASpace() throws {
        let draft = "@./READ"
        let query = try #require(FileMentionQuery(draft: draft, cursor: draft.endIndex))
        let result = query.draft(draft, inserting: "README.md")
        #expect(result.text == "@README.md ")
        #expect(result.cursor == result.text.endIndex)
    }

    @Test func aQuotedFolderCanContinueWithoutDuplicatingItsClosingQuote() throws {
        let draft = "👋🏽 @./My"
        let query = try #require(FileMentionQuery(draft: draft, cursor: draft.endIndex))
        let folder = query.draft(draft, inserting: "My Docs/")
        #expect(folder.text == "👋🏽 @\"My Docs/\"")
        #expect(String(folder.text[..<folder.cursor]) == "👋🏽 @\"My Docs/")
        let next = try #require(FileMentionQuery(draft: folder.text, cursor: folder.cursor))
        #expect(next.text == "My Docs/")
        let file = next.draft(folder.text, inserting: "My Docs/guide.md")
        #expect(file.text == "👋🏽 @\"My Docs/guide.md\" ")
        #expect(file.cursor == file.text.endIndex)
    }

    @Test(arguments: ["", "\u{00A0}"])
    func quotedFolderContinuationStaysEditableInTheReferenceProjection(padding: String) throws {
        let draft = "@README.md @./My next"
        let cursor = try #require(draft.range(of: " next")?.lowerBound)
        let query = try #require(FileMentionQuery(draft: draft, cursor: cursor))
        let folder = query.draft(draft, inserting: "My Docs/")
        var raw = folder.text
        var caret = raw.utf8.distance(from: raw.startIndex, to: folder.cursor)
        var projection = FileReferenceProjection(raw, editingAt: caret, tokenPadding: padding)
        for character in "guide" {
            let displayCaret = projection.displayOffset(caret)
            let index = projection.display.utf8.index(projection.display.startIndex, offsetBy: displayCaret)
            var typed = projection.display
            typed.insert(character, at: index)
            let edit = projection.replacingDisplay(with: typed)
            raw = edit.text
            caret = edit.caret
            projection = FileReferenceProjection(raw, editingAt: caret, tokenPadding: padding)
            let typedCaret = displayCaret + String(character).utf8.count
            #expect(projection.rawSelection(typedCaret..<typedCaret, showing: typed) == caret..<caret)
            #expect(projection.rawOffset(projection.displayOffset(caret)) == caret)
            let rawCursor = raw.utf8.index(raw.startIndex, offsetBy: caret)
            #expect(FileMentionQuery(draft: raw, cursor: rawCursor) != nil)
            #expect(projection.tokens.map(\.path) == ["README.md"])
        }
        #expect(raw == "@README.md @\"My Docs/guide\" next")
        let rawCursor = raw.utf8.index(raw.startIndex, offsetBy: caret)
        let fileQuery = try #require(FileMentionQuery(draft: raw, cursor: rawCursor))
        let file = fileQuery.draft(raw, inserting: "My Docs/guide.md")
        let fileCaret = file.text.utf8.distance(from: file.text.startIndex, to: file.cursor)
        let finished = FileReferenceProjection(file.text, editingAt: fileCaret, tokenPadding: padding)
        #expect(finished.tokens.map(\.path) == ["README.md", "My Docs/guide.md"])
    }

    @Test(arguments: ["hello@example.com", "@docs/ ", "@\"My Docs/\" "])
    func completedWordsDoNotOpenTheList(draft: String) {
        #expect(FileMentionQuery(draft: draft, cursor: draft.endIndex) == nil)
    }
}
