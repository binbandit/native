import Foundation
import Testing

@testable import CodeThemes

@Suite struct SpecimenLineTests {
    private let rich = "    if (attempt >= 3) throw new Error(\"failed\"); // retry"
    private let simple = "    const value = 3;"

    private func candidate(
        _ text: String, file: String = "chunker.ts", deleted: String? = nil
    ) -> SpecimenLine.Candidate {
        .init(
            file: file, project: "pier", language: .typeScript,
            deleted: deleted.map { [.init(number: 21, text: $0)] } ?? [],
            added: [.init(number: 21, text: text)])
    }

    @Test func richestLineWinsAndNewestBreaksTies() {
        let result = SpecimenLine.choose(from: [
            candidate(simple), candidate(rich, file: "new.ts"), candidate(rich, file: "old.ts"),
        ])
        #expect(result.file == "new.ts")
        #expect(result.added.first?.text == rich)
        #expect(!result.isSample)
    }

    @Test(arguments: [
        #""this isn't a short string and isn't a short string either""#,
        "API_KEY", "api-key", "apikey", "TOKEN", "secret", "password", "passw", "Bearer", "Authorization",
        "0123456789abcdef0123456789", "YWJjZGVmZ2hpamtsbW5vcHFy", "https://user:pw@host.test",
        "https://user@host.test", "\"this string literal is much longer than thirty two\"",
        "'this string literal is much longer than thirty two'", "`this string literal is much longer than thirty two`",
    ])
    func rejectsSecrets(_ value: String) {
        #expect(!SpecimenLine.isSafe(value))
        #expect(SpecimenLine.choose(from: [candidate("if (x > 3) print(\"\(value)\");")]).isSample)
    }

    @Test func boundsLengthAndPreservesIndentation() {
        #expect(
            SpecimenLine.choose(from: [candidate(String(repeating: " ", count: 8) + rich)]).added.first?.text.hasPrefix(
                "        ") == true)
        #expect(SpecimenLine.choose(from: [candidate(rich + String(repeating: " ", count: 65))]).isSample)
        #expect(SpecimenLine.choose(from: [candidate(rich + "\rhidden")]).isSample)
    }

    @Test func deletedLineComesFromSameHunkAndIsFiltered() {
        let old = rich.replacingOccurrences(of: ">=", with: "===")
        let result = SpecimenLine.choose(from: [candidate(rich, deleted: old)])
        #expect(result.deleted.first?.text == old)
        #expect(result.deleted.first?.number == 21)
        let unsafe = SpecimenLine.choose(from: [candidate(rich, deleted: "const secret = 'hidden';")])
        #expect(unsafe.deleted.allSatisfy { SpecimenLine.isSafe($0.text) })
        let onlyAdded = SpecimenLine.choose(from: [candidate(rich)])
        #expect(onlyAdded.deleted.first?.text == String(rich.dropLast()))
        #expect(onlyAdded.deleted.first?.number == nil)
    }

    @Test func adjacentLinesAndMetadataCannotLeakSecrets() {
        let input = SpecimenLine.Candidate(
            file: "chunker.ts", project: "pier", language: .typeScript,
            deleted: [.init(number: 1, text: "token = 123")],
            added: [.init(number: 1, text: "token = 456"), .init(number: 2, text: rich)])
        let result = SpecimenLine.choose(from: [input])
        #expect(result.added.contains { $0.text == rich })
        #expect((result.added + result.deleted).allSatisfy { SpecimenLine.isSafe($0.text) })
        #expect(SpecimenLine.choose(from: [candidate(rich, file: "api-key.ts")]).isSample)
    }

    @Test func derivesHunksAndNumbers() {
        let old = "unchanged\nold one\nold two\nunchanged\nother old\n"
        let new = "unchanged\nnew one\nnew two\nunchanged\nother new\n"
        let candidates = SpecimenLine.candidates(file: "chunker.ts", project: "pier", before: old, after: new)
        #expect(candidates.count == 2)
        #expect(candidates.first?.added.map(\.number) == [2, 3])
        #expect(candidates.first?.deleted.map(\.text) == ["old one", "old two"])
        #expect(candidates.last?.deleted.first?.number == 5)
        #expect(
            SpecimenLine.candidates(
                file: "chunker.ts", project: "pier", before: nil, after: String(repeating: "x", count: 100_001)
            ).isEmpty)
    }

    @Test(arguments: [CodeLanguage.typeScript, .swift, .python, .go, .rust])
    func fallbackUsesMostCommonLanguage(_ language: CodeLanguage) {
        let result = SpecimenLine.choose(from: [], recentLanguages: [.swift, language, language, .python])
        #expect(result.isSample)
        #expect(result.language == language)
        #expect(result.added.count == 2 && result.deleted.count == 2)
        #expect((result.added + result.deleted).allSatisfy { SpecimenLine.isSafe($0.text) })
        #expect(SpecimenLine.choose(from: []).language == .typeScript)
    }
}
