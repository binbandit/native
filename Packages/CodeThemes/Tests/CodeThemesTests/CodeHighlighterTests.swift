import Testing

@testable import CodeThemes

struct CodeHighlighterTests {
    /// The roles of the non-plain segments, in order, with their text.
    private func tokens(_ code: String, _ language: String) -> [String] {
        CodeHighlighter.segments(code, language: CodeLanguage.named(language))
            .filter { $0.role != .foreground && !$0.text.allSatisfy(\.isWhitespace) }
            .map { "\($0.role.rawValue):\($0.text)" }
    }

    @Test(arguments: [
        ("swift", "@MainActor func greet(_ name: String) -> String { \"Hi, \\(name)\" } // done\n/* a\nb */ let x = 0x1F"),
        ("ts", "const rows: string[] = parse(`a ${b}`, { bom: true }); // ok"),
        ("python", "@cache\ndef f(x):\n    \"\"\"Doc\n    more\"\"\"\n    return x ** 2  # square"),
        ("json", "{\"name\": \"Ada\", \"tags\": [1, 2.5, true, null]}"),
        ("diff", "--- a/x\n+++ b/x\n@@ -1 +1 @@\n-old\n+new\n context"),
        ("html", "<div class=\"a\">Tom &amp; Jerry<!-- note --></div>"),
        ("sh", "export PATH=\"$HOME/bin:${PATH}\" # path\necho 'it''s'"),
        ("rust", "fn main<'a>(x: &'a str) -> char { 'c' }"),
        ("yaml", "name: build\nsteps:\n  - run: make # go"),
        ("sql", "SELECT name FROM users WHERE id = 1 -- one"),
        ("swift", "let emoji = \"👩‍💻\"; let 名前 = 1"),
    ])
    func segmentsRebuildTheCode(language: String, code: String) {
        let segments = CodeHighlighter.segments(code, language: CodeLanguage.named(language))
        #expect(segments.map(\.text).joined() == code)
        #expect(segments.allSatisfy { !$0.text.isEmpty })
    }

    @Test func swiftRoles() {
        let code = "@MainActor func greet(_ name: String) -> Int { return 42 } // hi"
        #expect(
            tokens(code, "swift") == [
                "function:@MainActor", "keyword:func", "function:greet", "punctuation:(", "punctuation::",
                "type:String", "punctuation:)", "operator:->", "type:Int", "punctuation:{", "keyword:return",
                "constant:42", "punctuation:}", "comment:// hi",
            ])
    }

    @Test func stringsAndCommentsHideTheirContents() {
        #expect(tokens("let s = \"func // not\" // real", "swift").suffix(2) == ["string:\"func // not\"", "comment:// real"])
        #expect(tokens("x = '''a\n# b'''", "python").last == "string:'''a\n# b'''")
    }

    @Test func jsonKeysDifferFromValues() {
        #expect(tokens("{\"a\": \"b\", \"c\": null}", "json").filter { !$0.hasPrefix("punctuation") } == [
            "tag:\"a\"", "string:\"b\"", "tag:\"c\"", "constant:null",
        ])
    }

    @Test func diffColorsWholeLines() {
        let lines = CodeHighlighter.lines("--- a/f\n@@ -1 +1 @@\n-old\n+new\n same\n", language: .named("diff"))
        #expect(lines.map { $0.map(\.role) } == [[.comment], [.keyword], [.deletedForeground], [.insertedForeground], [.foreground]])
    }

    @Test func blockCommentsKeepTheirColorOnEveryLine() {
        let lines = CodeHighlighter.lines("/* one\ntwo */\nlet x", language: .named("swift"))
        #expect(lines.count == 3)
        #expect(lines[0].map(\.role) == [.comment])
        #expect(lines[1].map(\.role) == [.comment])
        #expect(lines[2].first?.role == .keyword)
    }

    @Test func rustLifetimesAreNotCharacters() {
        #expect(tokens("fn f<'a>(c: char) { 'x' }", "rust").contains("string:'x'"))
        #expect(!tokens("fn f<'a>(c: char) { 'x' }", "rust").contains { $0.hasPrefix("string:'a") })
    }

    @Test func languagesByNameAndPath() {
        #expect(CodeLanguage.named("TypeScript")?.id == "typescript")
        #expect(CodeLanguage.named("ts {highlight: 2}")?.id == "typescript")
        #expect(CodeLanguage.named("zsh")?.id == "shell")
        #expect(CodeLanguage.named("prose") == nil)
        #expect(CodeLanguage.forPath("native/Views/RootView.swift")?.id == "swift")
        #expect(CodeLanguage.forPath("Packages/x/Package.swift")?.id == "swift")
        #expect(CodeLanguage.forPath("README") == nil)
        #expect(CodeLanguage.forPath(".gitignore") == nil)
    }

    @Test func unknownLanguagesDrawPlain() {
        #expect(CodeHighlighter.segments("func x() {}", language: nil) == [CodeSegment("func x() {}", .foreground)])
        #expect(CodeHighlighter.segments("", language: .named("swift")).isEmpty)
    }

    @Test func preservingContrastKeepsEachRoleLegibleOnANewBackground() throws {
        let light = try #require(CodeTheme.native.light)
        let wool = CodeColor(rgb: 0xF1EDE6)
        let moved = light.preservingContrast(on: wool)
        #expect(moved.background == wool)
        for role in [CodeTokenRole.foreground, .comment, .keyword, .string, .constant, .function, .type, .tag] {
            #expect(moved[role].contrastRatio(with: wool) >= light[role].contrastRatio(with: light.background) - 0.01)
        }
        // Already legible colors don't move, and fills stay as they were.
        #expect(light.preservingContrast(on: light.background) == light)
        #expect(moved.insertedBackground == light.insertedBackground)
    }
}
