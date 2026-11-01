import Foundation
import Testing

@testable import TextInput

@Suite struct TextInputTests {
    @Test func tokensRoundTripAndDeleteAtomically() throws {
        let document = TextInputDocument(runs: [.text("Read "), .mention(path: "Sources/App.swift"), .text(" please")])
        #expect(document.displayText == "Read \u{FFFC} please")
        #expect(document.plainText == "Read @Sources/App.swift please")
        #expect(document.slice(NSRange(location: 5, length: 1))?.plainText == "@Sources/App.swift")
        #expect(document.replacing(NSRange(location: 5, length: 1), with: .init())?.plainText == "Read  please")
    }

    @Test func quotedPathsAndUnicodeSelections() {
        let document = TextInputDocument(runs: [.text("🧑🏽‍💻 日本語 "), .mention(path: "My Folder/日本語.swift")])
        #expect(document.plainText.hasSuffix("@\"My Folder/日本語.swift\""))
        #expect(document.slice(NSRange(location: 1, length: 1)) == nil)
        #expect(document.slice(NSRange(location: 0, length: document.displayText.utf16.count)) == document)
        #expect(document.replacing(NSRange(location: 999, length: 1), with: .init()) == nil)
        #expect(TextInputDocument(runs: [.text("a"), .text(""), .text("b")]) == TextInputDocument("ab"))
    }

    @Test(arguments: ["@", "@./", "@Sources/App", "hello @日本語", "hello /compact"])
    func queriesAtCaret(text: String) throws {
        let query = try #require(
            TextInputQuery(document: .init(text), selection: NSRange(location: text.utf16.count, length: 0)))
        #expect(query.text == (text.split(separator: " ").last.map { String($0.dropFirst()) } ?? ""))
        #expect(query.kind == (text.contains("@") ? .file : .command))
    }

    @Test(arguments: ["name@example.com", "https://example.com", "@path done", "/done ", "hello", "@\"closed\""])
    func noQuery(text: String) {
        #expect(TextInputQuery(document: .init(text), selection: NSRange(location: text.utf16.count, length: 0)) == nil)
    }

    @Test func caretMiddleSelectionIMEAndTokenBoundary() throws {
        let document = TextInputDocument(runs: [.mention(path: "a.swift"), .text(" @./Sources rest")])
        let selection = NSRange(location: 12, length: 0)
        let query = try #require(TextInputQuery(document: document, selection: selection))
        #expect(query.text == "./Sources")
        #expect(
            document.replacing(query.range, with: .init(runs: [.mention(path: "Sources/New.swift")]))?.plainText
                == "@a.swift @Sources/New.swift rest")
        #expect(TextInputQuery(document: document, selection: selection, isComposing: true) == nil)
        #expect(TextInputQuery(document: document, selection: NSRange(location: 3, length: 1)) == nil)
        #expect(
            TextInputQuery(document: .init("@\"My Folder"), selection: NSRange(location: 11, length: 0))?.text
                == "My Folder")
    }
}
