import Foundation
import SwiftTreeSitter

/// Colors code with a tree-sitter grammar: parses it, runs the grammar's highlight query and paints
/// each capture's role over the text, inner nodes over the nodes around them, then the languages it
/// embeds (a Markdown fence, an HTML script) over that. Nil when the parse fails or the grammar
/// loses its place, so `CodeHighlighter` can fall back to the lexer; an embedded language falls back
/// the same way, to the lexer for its range.
enum TreeSitterHighlighter {
    /// Embedded languages nest at most this deep (Markdown, its HTML block, that block's script).
    static let maximumDepth = 3

    static func segments(_ code: String, grammar: TreeSitterGrammar) -> [CodeSegment]? {
        // The wrapper bridges through Foundation; drain what it autoreleases on whichever thread runs this.
        autoreleasepool {
            var canvas = Canvas(code)
            guard paint(code, at: 0, grammar: grammar, on: &canvas, depth: 0) else { return nil }
            return canvas.segments()
        }
    }

    /// Paints `code`, which starts `offset` UTF-16 units into the canvas.
    private static func paint(
        _ code: String, at offset: Int, grammar: TreeSitterGrammar, on canvas: inout Canvas, depth: Int
    ) -> Bool {
        guard let queries = TreeSitterQueries.shared(grammar), let tree = parse(code, grammar: grammar),
            let root = tree.rootNode, !hasLostItsPlace(root)
        else { return false }

        let units = canvas.units
        let context = Predicate.Context(textProvider: { range, _ in
            units.text(at: offset + range.location, length: range.length)
        })
        for match in queries.highlights.execute(in: tree).resolve(with: context) {
            for capture in match.captures {
                guard let role = queries.roles[capture.index] else { continue }
                let range = capture.range
                let rank = Canvas.rank(depth: depth, length: range.length, pattern: capture.patternIndex)
                canvas.paint(offset + range.location, length: range.length, role, rank: rank)
            }
        }

        guard let injections = queries.injections, depth < maximumDepth else { return true }
        for injection in injections.execute(in: tree).resolve(with: context).injections() {
            let start = offset + injection.range.location
            guard injection.range.length > 0, let embedded = units.text(at: start, length: injection.range.length)
            else { continue }
            let language = CodeLanguage.named(injection.name)
            if let grammar = language?.treeSitter ?? TreeSitterGrammar(rawValue: injection.name),
                paint(embedded, at: start, grammar: grammar, on: &canvas, depth: depth + 1)
            {
                continue
            }
            if let language {
                canvas.paint(CodeLexer.segments(embedded, language: language), at: start, depth: depth + 1)
            }
        }
        return true
    }

    private static func parse(_ code: String, grammar: TreeSitterGrammar) -> MutableTree? {
        let parser = Parser()
        guard let language = grammar.language, (try? parser.setLanguage(language)) != nil else { return nil }
        // A pathological input gives up and falls back rather than holding a thread.
        parser.timeout = 0.5
        return parser.parse(code)
    }

    /// Code that isn't the language at all (prose under a wrong fence, pseudo-code) parses into error
    /// nodes, and a grammar that has lost its place colors worse than the lexer: past half the text in
    /// errors, or about one per line. A cut-off fragment (a hunk, a missing brace) costs one or two.
    private static func hasLostItsPlace(_ root: Node) -> Bool {
        guard root.hasError else { return false }
        let length = root.range.length
        let errors = errors(in: root)
        return errors.length * 2 > length || errors.count * 80 > length
    }

    /// Error nodes (not looking inside them) and missing tokens, and how much text the errors cover.
    private static func errors(in node: Node) -> (count: Int, length: Int) {
        if node.isMissing {
            return (1, 0)
        }
        if node.nodeType == "ERROR" {
            return (1, node.range.length)
        }
        guard node.hasError else { return (0, 0) }
        return (0..<node.childCount).compactMap { node.child(at: $0) }.map(errors(in:)).reduce((0, 0)) {
            ($0.count + $1.count, $0.length + $1.length)
        }
    }

    /// A role per UTF-16 unit, read back as segments. Where captures overlap, the higher rank shows,
    /// so they can paint in any order.
    private struct Canvas {
        let units: [UInt16]
        private var roles: [CodeTokenRole?]
        private var ranks: [UInt64]

        init(_ code: String) {
            units = Array(code.utf16)
            roles = Array(repeating: nil, count: units.count)
            ranks = Array(repeating: 0, count: units.count)
        }

        /// An embedded language over its host, then the innermost node, then for one node the later
        /// pattern, which is tree-sitter's rule.
        static func rank(depth: Int, length: Int, pattern: Int) -> UInt64 {
            UInt64(depth + 1) << 48 | UInt64(max(0, (1 << 24) - length)) << 20 | UInt64(min(pattern, (1 << 20) - 1))
        }

        mutating func paint(_ start: Int, length: Int, _ role: CodeTokenRole, rank: UInt64) {
            let end = min(start + length, roles.count)
            guard start >= 0, start < end else { return }
            for index in start..<end where rank >= ranks[index] {
                roles[index] = role
                ranks[index] = rank
            }
        }

        /// The lexer's colors for an embedded language it reads where no grammar could.
        mutating func paint(_ segments: [CodeSegment], at offset: Int, depth: Int) {
            var start = offset
            for segment in segments {
                let length = segment.text.utf16.count
                paint(start, length: length, segment.role, rank: Self.rank(depth: depth, length: length, pattern: 0))
                start += length
            }
        }

        func segments() -> [CodeSegment] {
            var segments: [CodeSegment] = []
            var start = 0
            while start < units.count {
                let role = roles[start] ?? .foreground
                var end = start + 1
                while end < units.count, (roles[end] ?? .foreground) == role { end += 1 }
                segments.append(CodeSegment(String(decoding: units[start..<end], as: UTF16.self), role))
                start = end
            }
            return segments
        }
    }
}

extension [UInt16] {
    /// The text of a run of UTF-16 units, or nil when it's out of bounds.
    fileprivate func text(at start: Int, length: Int) -> String? {
        guard start >= 0, length >= 0, start + length <= count else { return nil }
        return String(decoding: self[start..<start + length], as: UTF16.self)
    }
}
