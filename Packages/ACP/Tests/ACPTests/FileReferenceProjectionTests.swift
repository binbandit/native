import Testing

@testable import ACP

struct FileReferenceProjectionTests {
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
