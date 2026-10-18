/// What `CodeHighlighter` knows about a language: the tree-sitter grammar that parses it, when one is
/// bundled, and lexical rules for the lexer that colors everything else. Unknown languages draw as
/// plain text.
public struct CodeLanguage: Sendable, Hashable {
    /// How text in the language is scanned.
    enum Grammar: Sendable, Hashable {
        /// Comments, strings, numbers, keywords, types, calls and operators.
        case code
        /// Tags, attributes and comments (HTML, XML).
        case markup
        /// Whole lines: added, removed, hunk headers and file headers.
        case diff
        /// Headings, quotes, list markers, code spans, emphasis and links.
        case markdown
    }

    /// A quoted literal: its delimiter, whether a backslash escapes, and whether it may span lines.
    struct Quote: Sendable, Hashable {
        let delimiter: String
        var escapes = true
        var multiline = false
        /// A literal longer than this isn't one (Rust's `'a` lifetimes against `'a'` characters).
        var maxLength: Int?
    }

    public internal(set) var id: String
    let grammar: Grammar
    /// Parses the language for accurate colors; the lexer rules below are its fallback.
    var treeSitter: TreeSitterGrammar?
    var lineComments: [String] = []
    var blockComment: [String] = []
    var quotes: [Quote] = []
    var keywords: Set<String> = []
    var types: Set<String> = []
    var constants: Set<String> = []
    /// Capitalized identifiers are types (Swift, TypeScript, Java…).
    var capitalizedTypes = false
    /// `$name` is a variable (shell, PHP-like).
    var dollarVariables = false
    /// `@name` is a decorator or attribute, drawn as a function.
    var attributes = false
    /// A `key:` at the start of a line is a key (YAML, TOML's `key =` likewise).
    var lineKeys = false
    /// Quoted strings followed by a colon are keys (JSON).
    var quotedKeys = false
    var caseInsensitiveKeywords = false

    init(id: String, grammar: Grammar = .code) {
        self.id = id
        self.grammar = grammar
    }

    /// The language a Markdown fence names (`swift`, `ts`, `sh`…), or nil when it isn't one this knows.
    public static func named(_ name: String) -> CodeLanguage? {
        let key = name.split(whereSeparator: { $0 == " " || $0 == "{" || $0 == "," }).first.map(String.init) ?? name
        return aliases[key.lowercased()]
    }

    /// The language a file's extension implies, for diffs.
    public static func forPath(_ path: String) -> CodeLanguage? {
        let file = path.split(separator: "/").last.map(String.init) ?? path
        if let byName = fileNames[file] {
            return byName
        }
        guard let dot = file.lastIndex(of: "."), dot != file.startIndex else { return nil }
        return aliases[file[file.index(after: dot)...].lowercased()]
    }

    private static let fileNames: [String: CodeLanguage] = [
        "Makefile": .shell, "Dockerfile": .dockerfile, "Containerfile": .dockerfile, "Package.swift": .swift,
        ".zshrc": .bash, ".bashrc": .bash,
    ]

    private static let aliases: [String: CodeLanguage] = {
        var table: [String: CodeLanguage] = [:]
        let entries: [(CodeLanguage, [String])] = [
            (.swift, ["swift"]),
            (.typeScript, ["typescript", "ts", "mts", "cts"]),
            (.tsx, ["tsx"]),
            (.javaScript, ["javascript", "js", "jsx", "mjs", "cjs"]),
            (.python, ["python", "py", "pyi", "python3"]),
            (.go, ["go", "golang"]),
            (.rust, ["rust", "rs"]),
            (.java, ["java"]),
            (.kotlin, ["kotlin", "kt", "kts"]),
            (.c, ["c"]),
            (.cpp, ["cpp", "c++", "cc", "cxx", "hpp", "hh", "h"]),
            (.cFamily, ["objc", "objective-c", "m", "mm"]),
            (.cSharp, ["csharp", "cs", "c#"]),
            (.ruby, ["ruby", "rb"]),
            (.bash, ["bash", "sh", "zsh", "shell", "shellscript"]),
            // A transcript of commands and their output, or fish, isn't bash; the lexer reads both.
            (.shell, ["fish", "console", "terminal"]),
            (.json, ["json", "jsonc", "jsonl"]),
            (.json5, ["json5"]),
            (.yaml, ["yaml", "yml"]),
            (.toml, ["toml"]),
            (.html, ["html", "htm", "xhtml"]),
            (.markup, ["xml", "svg", "plist", "vue"]),
            (.css, ["css"]),
            (.scss, ["scss", "less"]),
            (.sql, ["sql", "sqlite", "postgres", "postgresql", "mysql"]),
            (.diff, ["diff", "patch"]),
            (.markdown, ["markdown", "md", "mdx"]),
            (.dockerfile, ["dockerfile", "docker", "containerfile"]),
        ]
        for (language, names) in entries {
            for name in names {
                table[name] = language
            }
        }
        return table
    }()
}
