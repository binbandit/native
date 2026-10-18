extension CodeTokenRole {
    /// The role for a highlight query's capture name (`keyword.function`, `string.special.key`),
    /// matched by its longest known prefix. Both naming schemes in the bundled queries are here:
    /// tree-sitter's (`text.title`, `conditional`) and nvim-treesitter's newer one (`markup.heading`,
    /// `keyword.conditional`). Nil means the capture doesn't color anything (`spell`, `_private`).
    init?(capture name: String) {
        var key = Substring(name)
        while !key.isEmpty {
            if let role = Self.captureRoles[key] {
                guard let role else { return nil }
                self = role
                return
            }
            key = key[..<(key.lastIndex(of: ".") ?? key.startIndex)]
        }
        return nil
    }

    /// Plain identifiers, properties and parameters stay the text color, as the lexer drew them, so
    /// code reads calmly; `embedded` and `none` reset a region (an interpolation, a fence's body) to it.
    private static let captureRoles: [Substring: CodeTokenRole?] = [
        "comment": .comment,
        "keyword": .keyword, "conditional": .keyword, "repeat": .keyword, "include": .keyword,
        "exception": .keyword, "storageclass": .keyword, "preproc": .keyword, "define": .keyword,
        "import": .keyword, "media": .keyword, "charset": .keyword, "keyframes": .keyword, "supports": .keyword,
        "string": .string, "character": .string, "text.literal": .string, "markup.raw": .string,
        "text.uri": .string, "markup.link.url": .string,
        "string.escape": .constant, "escape": .constant, "character.special": .constant,
        "string.special.symbol": .constant,
        "string.regex": .regex, "string.regexp": .regex, "string.special.regex": .regex, "regex": .regex,
        "string.special.key": .tag,
        "number": .constant, "float": .constant, "boolean": .constant, "constant": .constant, "label": .constant,
        "text.emphasis": .constant, "text.strong": .constant, "markup.italic": .constant, "markup.strong": .constant,
        "function": .function, "method": .function, "attribute": .function,
        "text.reference": .function, "markup.link": .function,
        "type": .type, "constructor": .type, "namespace": .type, "module": .type,
        "tag": .tag, "tag.attribute": .variable, "tag.delimiter": .punctuation, "tag.error": .invalid,
        "variable": .foreground, "variable.builtin": .keyword, "parameter": .foreground, "field": .foreground,
        "property": .foreground,
        "operator": .operator, "keyword.operator": .keyword,
        "punctuation": .punctuation, "delimiter": .punctuation, "punctuation.special": .keyword,
        "text.title": .keyword, "markup.heading": .keyword, "markup.quote": .comment, "markup.list": .punctuation,
        "embedded": .foreground, "none": .foreground,
        "spell": nil, "nospell": nil, "conceal": nil,
    ]
}
