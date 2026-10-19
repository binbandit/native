import SwiftTreeSitter
import TreeSitterBash
import TreeSitterC
import TreeSitterCSS
import TreeSitterGo
import TreeSitterHTML
import TreeSitterJSON
import TreeSitterJava
import TreeSitterJavaScript
import TreeSitterMarkdown
import TreeSitterMarkdownInline
import TreeSitterPython
import TreeSitterRust
import TreeSitterSwift
import TreeSitterTOML
import TreeSitterTSX
import TreeSitterTypeScript
import TreeSitterYAML

/// A tree-sitter grammar bundled with CodeThemes, with the highlight queries copied from its release
/// into `Queries/<folder>` (versions in Package.swift). The raw value is the name injections use.
enum TreeSitterGrammar: String, CaseIterable, Sendable {
    case swift, typescript, tsx, javascript, python, rust, go, json, bash, yaml, toml, html, css, markdown
    case markdownInline = "markdown_inline"
    case c, java

    /// The parser's tables; the C entry points return a pointer, which is never null in practice.
    var language: Language? {
        let pointer: OpaquePointer? =
            switch self {
            case .swift: tree_sitter_swift()
            case .typescript: tree_sitter_typescript()
            case .tsx: tree_sitter_tsx()
            case .javascript: tree_sitter_javascript()
            case .python: tree_sitter_python()
            case .rust: tree_sitter_rust()
            case .go: tree_sitter_go()
            case .json: tree_sitter_json()
            case .bash: tree_sitter_bash()
            case .yaml: tree_sitter_yaml()
            case .toml: tree_sitter_toml()
            case .html: tree_sitter_html()
            case .css: tree_sitter_css()
            case .markdown: tree_sitter_markdown()
            case .markdownInline: tree_sitter_markdown_inline()
            case .c: tree_sitter_c()
            case .java: tree_sitter_java()
            }
        return pointer.map { Language(language: $0) }
    }

    /// The highlight query files (`folder/name` without `.scm`), joined in this order. Later patterns
    /// win when two capture the same node, so a language's own refinements come after the base it
    /// extends, as TypeScript's do after JavaScript's.
    var highlightQueries: [String] {
        switch self {
        case .javascript:
            ["javascript/highlights", "javascript/highlights-jsx", "javascript/highlights-params"]
        case .typescript: ["javascript/highlights", "typescript/highlights"]
        case .tsx: ["javascript/highlights", "javascript/highlights-jsx", "typescript/highlights"]
        default: ["\(rawValue)/highlights"]
        }
    }

    /// The injection query, for grammars whose text embeds other languages (fences, script tags,
    /// the inline half of Markdown, macro bodies).
    var injectionQuery: String? {
        switch self {
        case .javascript, .typescript, .tsx: "javascript/injections"
        case .markdown, .markdownInline, .html, .rust: "\(rawValue)/injections"
        default: nil
        }
    }

    /// Where a capture's meaning depends on the language: keys are the structure of data and style
    /// files, an HTML or JSX attribute is a name rather than a decorator, a shell's `property` is a
    /// variable.
    func role(forCapture name: String) -> CodeTokenRole? {
        switch (self, name) {
        case (.yaml, "property"), (.toml, "property"), (.css, "property"): .tag
        case (.css, "variable"), (.bash, "property"): .variable
        case (.html, "attribute"), (.javascript, "attribute"), (.tsx, "attribute"): .variable
        case (.javascript, "string.special"), (.typescript, "string.special"), (.tsx, "string.special"): .regex
        default: CodeTokenRole(capture: name)
        }
    }
}
