import Testing

@testable import ACP

struct FileReferenceProjectionTests {
    @Test func chipPaddingStaysOutOfCanonicalDraftAndUndo() {
        let raw = "@folder/File.swift next"
        let padded = FileReferenceProjection(raw, tokenPadding: "\u{00A0}")
        #expect(padded.display == "\u{00A0}File.swift\u{00A0} next")
        #expect(padded.rawOffset(padded.display.utf8.count) == raw.utf8.count)
        #expect(padded.replacingDisplay(with: padded.display + "!").text == raw + "!")
        #expect(padded.replacingDisplay(with: String(padded.display.dropFirst())).text == " next")
        let removed = FileReferenceProjection(" next", tokenPadding: "\u{00A0}")
        let restored = padded.tokens.map {
            FileReferenceProjection.RestoredToken(display: $0.display, raw: "@" + $0.path)
        }
        #expect(removed.replacingDisplay(with: padded.display, restored: restored).text == raw)
    }

    @Test func typingAmongRepeatedCharactersKeepsTheEditorCaret() throws {
        let counts = ["a/File.swift": FileReferenceProjection.Counts(added: 6, removed: 2)]
        let value = FileReferenceProjection("@a/File.swift     call()\n", counts: counts)
        // A space typed right after the token's own space: the text diff puts the edit further on.
        let typed = "File.swift +6 −2      call()\n"
        let caret = "File.swift +6 −2  ".utf8.count
        let edit = value.replacingDisplay(with: typed)
        let next = FileReferenceProjection(edit.text, counts: counts)
        #expect(edit.text == "@a/File.swift      call()\n")
        #expect(next.rawSelection(caret..<caret, showing: typed) == 15..<15)
        #expect(FileReferenceProjection(edit.text).rawSelection(caret..<caret, showing: typed) == nil)
    }

    @Test func undoRestoresCanonicalTokenIdentity() {
        let raw = "Fix @folder/File.swift please"
        let original = FileReferenceProjection(raw, counts: ["folder/File.swift": .init(added: 6, removed: 2)])
        let removed = FileReferenceProjection("Fix  please")
        let restored = original.tokens.map {
            FileReferenceProjection.RestoredToken(display: $0.display, raw: "@" + $0.path)
        }
        #expect(removed.replacingDisplay(with: original.display, restored: restored).text == raw)
    }

    @Test func undoKeepsPathsWhenDisplayPrefixesAndSuffixesMatch() {
        let value = FileReferenceProjection("Fix File.swift please")
        let restored = FileReferenceProjection.RestoredToken(display: 4..<14, raw: "@folder/File.swift")
        #expect(
            value.replacingDisplay(with: "Fix File.swift please", restored: [restored]).text
                == "Fix @folder/File.swift please")
        let partlyTyped = FileReferenceProjection("Fix File.swift +6 please")
        let full = FileReferenceProjection.RestoredToken(
            display: 4..<(4 + "File.swift +6 −2".utf8.count), raw: "@folder/File.swift")
        #expect(
            partlyTyped.replacingDisplay(with: "Fix File.swift +6 −2 please", restored: [full]).text
                == "Fix @folder/File.swift please")
    }

    @Test func undoOfLiveCountUpdateKeepsThePath() {
        let value = FileReferenceProjection(
            "@folder/File.swift ", counts: ["folder/File.swift": .init(added: 7, removed: 2)])
        let old = FileReferenceProjection(
            "@folder/File.swift ", counts: ["folder/File.swift": .init(added: 6, removed: 2)])
        let restored = old.tokens.map { FileReferenceProjection.RestoredToken(display: $0.display, raw: "@" + $0.path) }
        #expect(value.replacingDisplay(with: old.display, restored: restored).text == value.raw)
    }

    @Test func tokenKeepsPathAndCountsOutOfPrompt() {
        let raw = "Fix @Packages/ACP/Prompt.swift and @\"a b.swift\" please"
        let value = FileReferenceProjection(raw, counts: ["Packages/ACP/Prompt.swift": .init(added: 6, removed: 2)])
        #expect(value.display == "Fix Prompt.swift +6 −2 and a b.swift please")
        #expect(value.replacingDisplay(with: value.display + "!").text == raw + "!")
        #expect(value.tokens.map(\.path) == ["Packages/ACP/Prompt.swift", "a b.swift"])
    }
    @Test func editingTokenDeletesEntireReference() {
        let value = FileReferenceProjection(
            "See @folder/File.swift please", counts: ["folder/File.swift": .init(added: 6, removed: 2)])
        #expect(value.replacingDisplay(with: "See File.swift +6 − please").text == "See  please")
        #expect(value.replacingDisplay(with: "See x please").text == "See x please")
    }
    @Test func punctuationRemainsOutsideKnownReference() {
        let projection = FileReferenceProjection(
            "See @folder/File.swift. Please", counts: ["folder/File.swift": .init(added: 2, removed: 1)])
        #expect(projection.display == "See File.swift +2 −1. Please")
        #expect(projection.tokens.first?.path == "folder/File.swift")
        #expect(projection.replacingDisplay(with: projection.display + "!").text == "See @folder/File.swift. Please!")
    }

    @Test func ignoresCodeEmailAndUnfinishedMentions() {
        let raw = "`@code.swift ` mail@example.com @folder/ @Partial"
        #expect(FileReferenceProjection(raw).display == raw)
    }
    @Test func unicodeSelectionsAndLiveCountsKeepCanonicalOffsets() {
        let raw = "👩🏽‍💻 @a/é.swift next"
        let first = FileReferenceProjection(raw)
        let live = FileReferenceProjection(raw, counts: ["a/é.swift": .init(added: 22, removed: 10)])
        for value in [first, live] {
            #expect(value.rawOffset(value.display.utf8.count) == raw.utf8.count)
            #expect(
                value.replacingDisplay(with: value.display.replacingOccurrences(of: "next", with: "later")).text
                    == "👩🏽‍💻 @a/é.swift later")
        }
    }
}
