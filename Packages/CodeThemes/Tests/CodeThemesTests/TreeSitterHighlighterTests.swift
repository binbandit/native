import Testing

@testable import CodeThemes

/// The cases a lexer can't get right, which are why highlighting parses with tree-sitter.
struct TreeSitterHighlighterTests {
    /// The role drawn over each occurrence of `text` in the code, in order; nil where it's mixed.
    private func roles(of text: String, in code: String, _ language: String) -> [CodeTokenRole?] {
        let segments = CodeHighlighter.segments(code, language: .named(language))
        let units = segments.flatMap { Array(repeating: $0.role, count: $0.text.utf16.count) }
        var roles: [CodeTokenRole?] = []
        var rest = code.startIndex..<code.endIndex
        while let found = code.range(of: text, range: rest) {
            let painted = Set(units[found.lowerBound.utf16Offset(in: code)..<found.upperBound.utf16Offset(in: code)])
            roles.append(painted.count == 1 ? painted.first : nil)
            rest = found.upperBound..<code.endIndex
        }
        return roles
    }

    @Test(arguments: TreeSitterGrammar.allCases)
    func everyGrammarsQueriesCompile(_ grammar: TreeSitterGrammar) throws {
        let queries = try TreeSitterQueries(grammar)
        #expect(queries.roles.contains { $0 != nil })
    }

    @Test(arguments: [
        ("tsx", "const App = () => <Card title=\"Hi\">{items.map((x) => <li key={x}>{x}</li>)}</Card>;"),
        ("cpp", "template <typename T> std::vector<std::map<int, T>> f(T a) { return {}; }"),
        ("markdown", "# Title\n\n```swift\nlet a = \"\\(b)\"\n```\n\n<div>hi</div>\n- **bold** `code`"),
        ("html", "<style>p { color: red }</style><script>let x = `${1}`</script><p class=a>&amp;</p>"),
        ("python", "s = f\"{a!r:>{width}} {'q'}\"  # 名前 👩‍💻"),
        ("swift", "let s = \"👩‍💻 \\(name) 名前\" /* never closed"),
    ])
    func segmentsRebuildTheCode(language: String, code: String) {
        let segments = CodeHighlighter.segments(code, language: .named(language))
        #expect(segments.map(\.text).joined() == code)
        #expect(segments.allSatisfy { !$0.text.isEmpty })
        #expect(zip(segments, segments.dropFirst()).allSatisfy { $0.role != $1.role })
    }

    @Test func tsxTagsAreMarkupNotComparisons() {
        let code = "const App = () => <div className=\"card\" onClick={() => go(1)}>Hi</div>;"
        #expect(roles(of: "div", in: code, "tsx") == [.tag, .tag])
        #expect(roles(of: "className", in: code, "tsx") == [.variable])
        #expect(roles(of: "\"card\"", in: code, "tsx") == [.string])
        #expect(roles(of: "go", in: code, "tsx") == [.function])
        #expect(roles(of: "Hi", in: code, "tsx") == [.foreground])
    }

    @Test func swiftInterpolationNestsStringsInCode() {
        let code = #"let s = "a \(b + "c \(d) e") f""#
        #expect(roles(of: "b", in: code, "swift") == [.foreground])
        #expect(roles(of: "d", in: code, "swift") == [.foreground])
        #expect(roles(of: "c ", in: code, "swift") == [.string])
        #expect(roles(of: " f", in: code, "swift") == [.string])
    }

    @Test func templateLiteralsNestInJavaScript() {
        let code = "const s = `a ${b + `c ${d} e`} f`;"
        #expect(roles(of: "b", in: code, "js") == [.foreground])
        #expect(roles(of: "d", in: code, "js") == [.foreground])
        #expect(roles(of: "c ", in: code, "js") == [.string])
        #expect(roles(of: " f", in: code, "js") == [.string])
    }

    @Test func pythonFStringsNest() {
        let code = #"s = f"a {b + f'c {d}'} e""#
        #expect(roles(of: "b", in: code, "python") == [.foreground])
        #expect(roles(of: "d", in: code, "python") == [.foreground])
        #expect(roles(of: " e", in: code, "python") == [.string])
    }

    /// C++, Kotlin and Ruby are lexed, on their own and in a fence: their grammars were 9.6 MB of the
    /// app (docs/app-size.md).
    @Test(arguments: [
        ("cpp", "template <typename T> class Box { int value; };", "class"),
        ("kotlin", "fun main() { val answer = 42 }", "fun"),
        ("ruby", "def greet(name)\n  puts name\nend", "def"),
    ])
    func languagesLeftOnTheLexerStillColorTheirKeywords(language: String, code: String, keyword: String) throws {
        let lexed = try #require(CodeLanguage.named(language))
        #expect(lexed.treeSitter == nil)
        #expect(CodeHighlighter.segments(code, language: lexed) == CodeLexer.segments(code, language: lexed))
        #expect(roles(of: keyword, in: code, language) == [.keyword])
        #expect(roles(of: keyword, in: "```\(language)\n\(code)\n```\n", "md") == [.keyword])
    }

    @Test func markdownFencesHighlightTheirLanguage() {
        let code = "## Setup\n\nRun `make`, then:\n\n```swift\nlet answer = 42 // yes\n```\n"
        #expect(roles(of: "Setup", in: code, "md") == [.keyword])
        #expect(roles(of: "make", in: code, "md") == [.string])
        #expect(roles(of: "let", in: code, "md") == [.keyword])
        #expect(roles(of: "answer", in: code, "md") == [.foreground])
        #expect(roles(of: "42", in: code, "md") == [.constant])
        #expect(roles(of: "// yes", in: code, "md") == [.comment])
    }

    @Test func keysInDataFilesDifferFromValues() {
        #expect(roles(of: "\"name\"", in: "{\"name\": \"native\"}", "json") == [.tag])
        #expect(roles(of: "\"native\"", in: "{\"name\": \"native\"}", "json") == [.string])
        #expect(roles(of: "name", in: "name = \"native\"\nbuild.target = 1", "toml") == [.tag])
        #expect(roles(of: "target", in: "name = \"native\"\nbuild.target = 1", "toml") == [.tag])
        #expect(roles(of: "name", in: "name: native\nsteps: [a]", "yaml") == [.tag])
    }

    @Test func htmlScriptsAndStylesAreTheirOwnLanguages() {
        let code = "<script>const n = 1;</script><style>p { color: red; }</style>"
        #expect(roles(of: "script", in: code, "html") == [.tag, .tag])
        #expect(roles(of: "const", in: code, "html") == [.keyword])
        #expect(roles(of: "color", in: code, "html") == [.tag])
    }

    @Test func languagesWithoutAGrammarUseTheLexer() throws {
        let code = "FROM swift:6 AS build\nRUN swift build"
        let dockerfile = try #require(CodeLanguage.named("dockerfile"))
        #expect(dockerfile.treeSitter == nil)
        #expect(CodeHighlighter.segments(code, language: dockerfile) == CodeLexer.segments(code, language: dockerfile))
    }

    @Test func codeAGrammarCantParseUsesTheLexer() throws {
        // Prose under a `swift` fence parses into errors; the lexer colors it evenly instead.
        let prose = "Then it's done: we'll ship, if (and only if) the tests pass."
        let swift = try #require(CodeLanguage.named("swift"))
        #expect(TreeSitterHighlighter.segments(prose, grammar: .swift) == nil)
        #expect(CodeHighlighter.segments(prose, language: swift) == CodeLexer.segments(prose, language: swift))
    }

    @Test func aCutOffFragmentStillParses() {
        // A diff hunk: the function never closes, so tree-sitter wraps all of it in one error node.
        let hunk = """
            export function Card({ title }: Props) {
              const label = `${title} (${n})`;
              return (
                <section className="card">
                  <h2>{label}</h2>
            """
        #expect(TreeSitterHighlighter.segments(hunk, grammar: .tsx) != nil)
        #expect(roles(of: "section", in: hunk, "tsx") == [.tag])
        #expect(roles(of: "title", in: hunk, "tsx") == [.foreground, .foreground])
    }

    @Test func fencesInLanguagesWithoutAGrammarUseTheLexer() {
        let code = "```diff\n-old\n+new\n```\n"
        #expect(roles(of: "-old", in: code, "md") == [.deletedForeground])
        #expect(roles(of: "+new", in: code, "md") == [.insertedForeground])
    }
}
