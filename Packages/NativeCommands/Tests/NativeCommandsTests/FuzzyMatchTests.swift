import Testing

@testable import NativeCommands

@Suite struct FuzzyMatchTests {
    private func score(_ query: String, _ title: String, keywords: [String] = []) -> Int? {
        FuzzyMatch(query, title: title, keywords: keywords)?.score
    }

    @Test func tiersRankCloserMatchesFirst() {
        let ranked = [
            score("archive task", "Archive Task"),
            score("arch", "Archive Task"),
            score("task", "Archive Task"),
            score("at", "Archive Task"),
            score("chive", "Archive Task"),
            score("task arch", "Archive Task"),
            score("hide", "Archive Task", keywords: ["hide"]),
            score("ide", "Archive Task", keywords: ["hide"]),
            score("atsk", "Archive Task"),
        ].compactMap { $0 }
        #expect(ranked.count == 9)
        #expect(ranked == ranked.sorted(by: >))
        #expect(Set(ranked).count == ranked.count)
    }

    @Test func lettersInOrderStillMatch() throws {
        let match = try #require(FuzzyMatch("nwse", title: "New Session"))
        #expect(match.score > 0 && match.score < 35)
        #expect(match.highlights == [0..<1, 2..<3, 4..<6])
        #expect(FuzzyMatch("xyz", title: "New Session") == nil)
    }

    @Test func highlightsTheMatchedLetters() {
        #expect(FuzzyMatch("sess", title: "New Session")?.highlights == [4..<8])
        #expect(FuzzyMatch("ns", title: "New Session")?.highlights == [0..<1, 4..<5])
    }

    @Test func emptyQueryMatchesEverything() {
        #expect(score("", "Anything") == 0)
        #expect(score("  ", "Anything") == 0)
    }

    @Test func caseDoesNotMatter() {
        #expect(score("NEW", "new session") == score("new", "New Session"))
    }
}
