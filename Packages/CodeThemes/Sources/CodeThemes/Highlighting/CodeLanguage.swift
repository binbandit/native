/// What `CodeHighlighter` knows about a language: enough lexical rules to color the common languages
/// agents write, not a parser. Unknown languages draw as plain text.
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
        ".zshrc": .shell, ".bashrc": .shell,
    ]

    private static let aliases: [String: CodeLanguage] = {
        var table: [String: CodeLanguage] = [:]
        let entries: [(CodeLanguage, [String])] = [
            (.swift, ["swift"]),
            (.typeScript, ["typescript", "ts", "tsx", "mts", "cts"]),
            (.javaScript, ["javascript", "js", "jsx", "mjs", "cjs"]),
            (.python, ["python", "py", "pyi", "python3"]),
            (.go, ["go", "golang"]),
            (.rust, ["rust", "rs"]),
            (.java, ["java"]),
            (.kotlin, ["kotlin", "kt", "kts"]),
            (.cFamily, ["c", "h", "cpp", "c++", "cc", "cxx", "hpp", "hh", "objc", "objective-c", "m", "mm"]),
            (.cSharp, ["csharp", "cs", "c#"]),
            (.ruby, ["ruby", "rb"]),
            (.shell, ["shell", "sh", "bash", "zsh", "fish", "console", "shellscript", "terminal"]),
            (.json, ["json", "jsonc", "json5", "jsonl"]),
            (.yaml, ["yaml", "yml"]),
            (.toml, ["toml"]),
            (.markup, ["html", "htm", "xml", "svg", "plist", "vue", "xhtml"]),
            (.css, ["css", "scss", "less"]),
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

// MARK: - Languages

extension CodeLanguage {
    private static let doubleQuote = Quote(delimiter: "\"")
    private static let singleQuote = Quote(delimiter: "'")
    private static let backtick = Quote(delimiter: "`", multiline: true)
    private static let cConstants: Set<String> = ["true", "false", "null", "nil", "NULL", "nullptr"]

    static let swift: CodeLanguage = {
        var language = CodeLanguage(id: "swift")
        language.lineComments = ["//"]
        language.blockComment = ["/*", "*/"]
        language.quotes = [Quote(delimiter: "\"\"\"", multiline: true), doubleQuote]
        language.keywords = [
            "actor", "any", "as", "associatedtype", "async", "await", "break", "case", "catch", "class", "continue",
            "default", "defer", "deinit", "do", "else", "enum", "extension", "fallthrough", "fileprivate", "final",
            "for", "func", "guard", "if", "import", "in", "init", "inout", "internal", "is", "isolated", "let",
            "lazy", "mutating", "nonisolated", "nonmutating", "open", "operator", "override", "private", "protocol",
            "public", "repeat", "rethrows", "return", "self", "Self", "some", "static", "struct", "subscript",
            "super", "switch", "throw", "throws", "try", "typealias", "var", "weak", "where", "while", "consuming",
            "borrowing", "sending", "package", "macro", "get", "set", "willSet", "didSet",
        ]
        language.constants = ["true", "false", "nil"]
        language.capitalizedTypes = true
        language.attributes = true
        return language
    }()

    static let typeScript: CodeLanguage = {
        var language = javaScript
        language = CodeLanguage(copying: language, id: "typescript")
        language.keywords.formUnion([
            "interface", "type", "enum", "implements", "namespace", "declare", "readonly", "abstract", "private",
            "protected", "public", "keyof", "infer", "satisfies", "as", "is", "asserts", "override", "module",
        ])
        language.types = [
            "string", "number", "boolean", "void", "unknown", "never", "any", "object", "bigint", "symbol",
        ]
        return language
    }()

    static let javaScript: CodeLanguage = {
        var language = CodeLanguage(id: "javascript")
        language.lineComments = ["//"]
        language.blockComment = ["/*", "*/"]
        language.quotes = [doubleQuote, singleQuote, backtick]
        language.keywords = [
            "async", "await", "break", "case", "catch", "class", "const", "continue", "debugger", "default", "delete",
            "do", "else", "export", "extends", "finally", "for", "from", "function", "if", "import", "in",
            "instanceof", "let", "new", "of", "return", "static", "super", "switch", "this", "throw", "try",
            "typeof", "var", "void", "while", "with", "yield", "get", "set",
        ]
        language.constants = ["true", "false", "null", "undefined", "NaN", "Infinity"]
        language.capitalizedTypes = true
        language.attributes = true
        return language
    }()

    static let python: CodeLanguage = {
        var language = CodeLanguage(id: "python")
        language.lineComments = ["#"]
        language.quotes = [
            Quote(delimiter: "\"\"\"", multiline: true), Quote(delimiter: "'''", multiline: true), doubleQuote,
            singleQuote,
        ]
        language.keywords = [
            "and", "as", "assert", "async", "await", "break", "class", "continue", "def", "del", "elif", "else",
            "except", "finally", "for", "from", "global", "if", "import", "in", "is", "lambda", "nonlocal", "not",
            "or", "pass", "raise", "return", "try", "while", "with", "yield", "match", "case", "self", "cls",
        ]
        language.types = ["int", "str", "float", "bool", "list", "dict", "set", "tuple", "bytes", "object", "type"]
        language.constants = ["True", "False", "None"]
        language.capitalizedTypes = true
        language.attributes = true
        return language
    }()

    static let go: CodeLanguage = {
        var language = CodeLanguage(id: "go")
        language.lineComments = ["//"]
        language.blockComment = ["/*", "*/"]
        language.quotes = [doubleQuote, Quote(delimiter: "`", escapes: false, multiline: true), singleQuote]
        language.keywords = [
            "break", "case", "chan", "const", "continue", "default", "defer", "else", "fallthrough", "for", "func",
            "go", "goto", "if", "import", "interface", "map", "package", "range", "return", "select", "struct",
            "switch", "type", "var",
        ]
        language.types = [
            "bool", "byte", "complex64", "complex128", "error", "float32", "float64", "int", "int8", "int16", "int32",
            "int64", "rune", "string", "uint", "uint8", "uint16", "uint32", "uint64", "uintptr", "any",
        ]
        language.constants = ["true", "false", "nil", "iota"]
        return language
    }()

    static let rust: CodeLanguage = {
        var language = CodeLanguage(id: "rust")
        language.lineComments = ["//"]
        language.blockComment = ["/*", "*/"]
        language.quotes = [doubleQuote, Quote(delimiter: "'", maxLength: 4)]
        language.keywords = [
            "as", "async", "await", "break", "const", "continue", "crate", "dyn", "else", "enum", "extern", "fn",
            "for", "if", "impl", "in", "let", "loop", "match", "mod", "move", "mut", "pub", "ref", "return", "self",
            "Self", "static", "struct", "super", "trait", "type", "unsafe", "use", "where", "while",
        ]
        language.types = [
            "i8", "i16", "i32", "i64", "i128", "isize", "u8", "u16", "u32", "u64", "u128", "usize", "f32", "f64",
            "bool", "char", "str",
        ]
        language.constants = ["true", "false", "None", "Some", "Ok", "Err"]
        language.capitalizedTypes = true
        return language
    }()

    static let java: CodeLanguage = {
        var language = CodeLanguage(id: "java")
        language.lineComments = ["//"]
        language.blockComment = ["/*", "*/"]
        language.quotes = [Quote(delimiter: "\"\"\"", multiline: true), doubleQuote, singleQuote]
        language.keywords = [
            "abstract", "assert", "break", "case", "catch", "class", "continue", "default", "do", "else", "enum",
            "extends", "final", "finally", "for", "if", "implements", "import", "instanceof", "interface", "native",
            "new", "package", "private", "protected", "public", "record", "return", "static", "super", "switch",
            "synchronized", "this", "throw", "throws", "try", "var", "void", "volatile", "while", "yield",
        ]
        language.types = ["boolean", "byte", "char", "double", "float", "int", "long", "short"]
        language.constants = cConstants
        language.capitalizedTypes = true
        language.attributes = true
        return language
    }()

    static let kotlin: CodeLanguage = {
        var language = CodeLanguage(copying: java, id: "kotlin")
        language.keywords.formUnion([
            "fun", "val", "object", "companion", "data", "sealed", "when", "is", "in", "as", "suspend", "override",
            "open", "internal", "lateinit", "typealias", "init",
        ])
        return language
    }()

    static let cFamily: CodeLanguage = {
        var language = CodeLanguage(id: "c")
        language.lineComments = ["//"]
        language.blockComment = ["/*", "*/"]
        language.quotes = [doubleQuote, singleQuote]
        language.keywords = [
            "auto", "break", "case", "catch", "class", "const", "constexpr", "continue", "default", "delete", "do",
            "else", "enum", "explicit", "extern", "for", "friend", "goto", "if", "inline", "namespace", "new",
            "operator", "private", "protected", "public", "return", "sizeof", "static", "struct", "switch",
            "template", "this", "throw", "try", "typedef", "typename", "union", "using", "virtual", "volatile",
            "while", "#include", "#define", "#if", "#ifdef", "#ifndef", "#endif", "#else", "#pragma", "#import",
            "@interface", "@implementation", "@end", "@property", "self",
        ]
        language.types = [
            "void", "char", "short", "int", "long", "float", "double", "signed", "unsigned", "bool", "size_t",
            "int8_t", "int16_t", "int32_t", "int64_t", "uint8_t", "uint16_t", "uint32_t", "uint64_t", "id", "BOOL",
        ]
        language.constants = cConstants.union(["YES", "NO"])
        language.capitalizedTypes = true
        return language
    }()

    static let cSharp: CodeLanguage = {
        var language = CodeLanguage(copying: java, id: "csharp")
        language.keywords.formUnion([
            "using", "namespace", "async", "await", "var", "readonly", "override", "virtual", "sealed", "get", "set",
            "init", "record", "struct", "ref", "out", "in", "is", "as", "base", "internal", "params", "partial",
        ])
        language.types.formUnion(["string", "decimal", "object", "uint", "ulong", "ushort", "sbyte", "dynamic"])
        return language
    }()

    static let ruby: CodeLanguage = {
        var language = CodeLanguage(id: "ruby")
        language.lineComments = ["#"]
        language.quotes = [doubleQuote, singleQuote]
        language.keywords = [
            "alias", "and", "begin", "break", "case", "class", "def", "defined?", "do", "else", "elsif", "end",
            "ensure", "for", "if", "in", "module", "next", "not", "or", "redo", "rescue", "retry", "return", "self",
            "super", "then", "undef", "unless", "until", "when", "while", "yield", "require", "attr_reader",
            "attr_accessor",
        ]
        language.constants = ["true", "false", "nil"]
        language.capitalizedTypes = true
        return language
    }()

    static let shell: CodeLanguage = {
        var language = CodeLanguage(id: "shell")
        language.lineComments = ["#"]
        language.quotes = [doubleQuote, Quote(delimiter: "'", escapes: false)]
        language.keywords = [
            "if", "then", "else", "elif", "fi", "for", "while", "until", "do", "done", "case", "esac", "in",
            "function", "return", "export", "local", "readonly", "set", "unset", "source", "alias", "exit", "cd",
            "echo", "printf", "sudo", "end",
        ]
        language.dollarVariables = true
        return language
    }()

    static let json: CodeLanguage = {
        var language = CodeLanguage(id: "json")
        language.lineComments = ["//"]
        language.quotes = [doubleQuote]
        language.constants = ["true", "false", "null"]
        language.quotedKeys = true
        return language
    }()

    static let yaml: CodeLanguage = {
        var language = CodeLanguage(id: "yaml")
        language.lineComments = ["#"]
        language.quotes = [doubleQuote, Quote(delimiter: "'", escapes: false)]
        language.constants = ["true", "false", "null", "yes", "no", "on", "off", "~"]
        language.lineKeys = true
        return language
    }()

    static let toml: CodeLanguage = {
        var language = yaml
        language = CodeLanguage(copying: language, id: "toml")
        language.quotes = [
            Quote(delimiter: "\"\"\"", multiline: true), doubleQuote, Quote(delimiter: "'", escapes: false),
        ]
        language.constants = ["true", "false"]
        return language
    }()

    static let css: CodeLanguage = {
        var language = CodeLanguage(id: "css")
        language.lineComments = ["//"]
        language.blockComment = ["/*", "*/"]
        language.quotes = [doubleQuote, singleQuote]
        language.keywords = [
            "@media", "@import", "@supports", "@keyframes", "@font-face", "!important", "@use", "@mixin",
        ]
        language.lineKeys = true
        return language
    }()

    static let sql: CodeLanguage = {
        var language = CodeLanguage(id: "sql")
        language.lineComments = ["--"]
        language.blockComment = ["/*", "*/"]
        language.quotes = [Quote(delimiter: "'", escapes: false), doubleQuote]
        language.keywords = [
            "select", "from", "where", "and", "or", "not", "insert", "into", "values", "update", "set", "delete",
            "create", "table", "index", "view", "drop", "alter", "add", "join", "left", "right", "inner", "outer",
            "on", "group", "by", "order", "having", "limit", "offset", "as", "distinct", "union", "all", "case",
            "when", "then", "else", "end", "primary", "key", "foreign", "references", "default", "unique", "with",
            "returning", "exists", "in", "is", "like", "between", "asc", "desc", "begin", "commit", "rollback",
        ]
        language.types = ["integer", "int", "text", "varchar", "boolean", "real", "blob", "timestamp", "date", "uuid"]
        language.constants = ["null", "true", "false"]
        language.caseInsensitiveKeywords = true
        return language
    }()

    static let markup: CodeLanguage = CodeLanguage(id: "markup", grammar: .markup)

    static let diff: CodeLanguage = CodeLanguage(id: "diff", grammar: .diff)

    static let markdown: CodeLanguage = CodeLanguage(id: "markdown", grammar: .markdown)

    static let dockerfile: CodeLanguage = {
        var language = CodeLanguage(copying: shell, id: "dockerfile")
        language.keywords.formUnion([
            "FROM", "RUN", "CMD", "LABEL", "EXPOSE", "ENV", "ADD", "COPY", "ENTRYPOINT", "VOLUME", "USER", "WORKDIR",
            "ARG", "ONBUILD", "STOPSIGNAL", "HEALTHCHECK", "SHELL", "AS", "MAINTAINER",
        ])
        return language
    }()

    /// Another language's rules under a new id.
    private init(copying other: CodeLanguage, id: String) {
        self = other
        self.id = id
    }
}
