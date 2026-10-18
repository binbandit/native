import Testing

@testable import Search

struct SearchTextTests {
    @Test func splitsIdentifiersIntoTheirWords() {
        #expect(SearchText.codeParts(of: "SessionStore.swift parseHTTPHeader") == "session store parse http header")
        #expect(SearchText.codeParts(of: "plain words and snake_case stay out") == "")
        #expect(SearchText.codeParts(of: "AppModel appModel") == "app model")
    }

    @Test func wordsMatchTheTokenizer() {
        #expect(SearchText.words(in: "native/Models/AppModel.swift") == ["native", "models", "appmodel", "swift"])
        #expect(SearchText.words(in: "git rebase -i") == ["git", "rebase", "i"])
    }

    @Test func capsKeepTheEnd() {
        let text = String(repeating: "a", count: 100) + "END"
        let capped = SearchText.capped(text, to: 40)
        #expect(capped.count < 50)
        #expect(capped.hasSuffix("END"))
    }

    @Test func snippetsMarkMatchesInsideIdentifiers() {
        let snippet = SearchSnippet(text: "Opened AppModel.swift to fix it", words: ["model"])
        #expect(snippet.runs.filter(\.isMatch).map(\.text) == ["Model"])
        #expect(snippet.text == "Opened AppModel.swift to fix it")
    }

    @Test func shortWordsMatchWholeWordsAndPhrasesReadAsOne() {
        let snippet = SearchSnippet(
            text: "Another one: they ran the kumquat-lighthouse check", words: ["the", "kumquat", "lighthouse"])
        #expect(snippet.runs.filter(\.isMatch).map(\.text) == ["the kumquat-lighthouse"])
        let typing = SearchSnippet(text: "the rollback", words: ["ro"], prefixes: ["ro"])
        #expect(typing.runs.filter(\.isMatch).map(\.text) == ["ro"])
    }

    @Test func longTextIsCutAroundTheMatch() {
        let text =
            String(repeating: "filler words here ", count: 40) + "the login timeout"
            + String(repeating: " tail", count: 60)
        let snippet = SearchSnippet(text: text, words: ["timeout"], width: 80)
        #expect(snippet.text.hasPrefix("…"))
        #expect(snippet.text.hasSuffix("…"))
        #expect(snippet.runs.contains { $0.isMatch && $0.text == "timeout" })
    }
}
