/// A run of code drawn in one role's color.
public struct CodeSegment: Sendable, Hashable {
    public let text: String
    public let role: CodeTokenRole

    public init(_ text: String, _ role: CodeTokenRole) {
        self.text = text
        self.role = role
    }
}

/// Colors code by role with a small lexer per language (`CodeLanguage`): comments, strings, numbers,
/// keywords, types, calls, operators, markup tags and diff lines. It works on any fragment, never
/// fails, and draws what it doesn't recognize as plain text, so a wrong guess costs color, not text.
public enum CodeHighlighter {
    /// Code past this many characters draws plain, so a pasted log can't stall a frame.
    public static let maximumLength = 200_000

    /// The code as consecutive segments; joined, their text is exactly `code`.
    public static func segments(_ code: String, language: CodeLanguage?) -> [CodeSegment] {
        guard let language, code.utf8.count <= maximumLength else {
            return code.isEmpty ? [] : [CodeSegment(code, .foreground)]
        }
        var lexer = Lexer(scalars: Array(code.unicodeScalars), language: language)
        return lexer.run()
    }

    /// The code's lines, each as segments (without the line break), for drawing line by line (diffs).
    /// Tokens spanning lines, like block comments, keep their color on every line.
    public static func lines(_ code: String, language: CodeLanguage?) -> [[CodeSegment]] {
        var lines: [[CodeSegment]] = [[]]
        for segment in segments(code, language: language) {
            let parts = segment.text.split(separator: "\n", omittingEmptySubsequences: false)
            for (index, part) in parts.enumerated() {
                if index > 0 {
                    lines.append([])
                }
                if !part.isEmpty {
                    lines[lines.count - 1].append(CodeSegment(String(part), segment.role))
                }
            }
        }
        if code.hasSuffix("\n") {
            lines.removeLast()
        }
        return lines
    }
}

private struct Lexer {
    let scalars: [Unicode.Scalar]
    let language: CodeLanguage
    private var position = 0
    private var segments: [CodeSegment] = []
    /// Where unclassified text began; flushed as plain text before the next token.
    private var plainStart = 0
    /// The previous word was `func`, `def`, `fn`…, so the next identifier names a function.
    private var expectsFunctionName = false
    /// A markup tag is open: its words are attributes until `>`.
    private var isInTag = false

    init(scalars: [Unicode.Scalar], language: CodeLanguage) {
        self.scalars = scalars
        self.language = language
    }

    mutating func run() -> [CodeSegment] {
        switch language.grammar {
        case .diff: scanDiff()
        case .markup: scanMarkup()
        case .code: scanCode()
        }
        flushPlain()
        return segments
    }

    // MARK: Code

    private mutating func scanCode() {
        while position < scalars.count {
            if let close = commentClose() {
                emit(until: close, .comment)
            } else if let quote = quoteAt(position), let end = quoteEnd(quote) {
                let role: CodeTokenRole = language.quotedKeys && isFollowedByColon(end) ? .tag : .string
                emit(until: end, role)
            } else if isLineKey() {
                emitLineKey()
            } else if isDigit(scalars[position]) {
                emit(until: numberEnd(), .constant)
            } else if language.dollarVariables, scalars[position] == "$", position + 1 < scalars.count,
                isWordStart(scalars[position + 1]) || scalars[position + 1] == "{"
            {
                emit(until: variableEnd(), .variable)
            } else if language.attributes, scalars[position] == "@", position + 1 < scalars.count,
                isWordStart(scalars[position + 1])
            {
                emit(until: wordEnd(from: position + 1), .function)
            } else if isWordStart(scalars[position]) || scalars[position] == "#" && isWordStart(next) {
                scanWord()
            } else if isOperator(scalars[position]) {
                var end = position + 1
                while end < scalars.count, isOperator(scalars[end]) { end += 1 }
                emit(until: end, .operator)
            } else if "{}[]();,.:".unicodeScalars.contains(scalars[position]) {
                emit(until: position + 1, .punctuation)
            } else {
                position += 1
            }
        }
    }

    private mutating func scanWord() {
        let end = wordEnd(from: position + 1)
        let word = String(String.UnicodeScalarView(scalars[position..<end]))
        let lookup = language.caseInsensitiveKeywords ? word.lowercased() : word
        let role: CodeTokenRole?
        if language.keywords.contains(lookup) {
            role = .keyword
        } else if language.constants.contains(lookup) {
            role = .constant
        } else if language.types.contains(lookup) {
            role = .type
        } else if expectsFunctionName || isFollowed(by: "(", at: end) {
            role = .function
        } else if language.capitalizedTypes, let first = word.unicodeScalars.first, first.properties.isUppercase {
            role = .type
        } else {
            role = nil
        }
        expectsFunctionName = ["func", "def", "fn", "function", "fun"].contains(word)
        if let role {
            emit(until: end, role)
        } else {
            position = end
        }
    }

    /// The end of a comment starting here, or nil when none does.
    private func commentClose() -> Int? {
        if language.blockComment.count == 2, matches(language.blockComment[0], at: position) {
            let closing = language.blockComment[1]
            var end = position + language.blockComment[0].unicodeScalars.count
            while end < scalars.count, !matches(closing, at: end) { end += 1 }
            return min(end + closing.unicodeScalars.count, scalars.count)
        }
        for prefix in language.lineComments where matches(prefix, at: position) {
            // `#` starts a shell comment only at a word boundary (`a#b` and `${#x}` aren't comments).
            if prefix == "#", position > 0, !isSpace(scalars[position - 1]) { continue }
            return lineEnd(from: position)
        }
        return nil
    }

    private func quoteAt(_ index: Int) -> CodeLanguage.Quote? {
        language.quotes.first { matches($0.delimiter, at: index) }
    }

    /// The end of a literal opened here, or nil when it isn't one (an apostrophe in prose, a lifetime).
    private func quoteEnd(_ quote: CodeLanguage.Quote) -> Int? {
        let width = quote.delimiter.unicodeScalars.count
        var end = position + width
        while end < scalars.count {
            if quote.escapes, scalars[end] == "\\" {
                end += 2
                continue
            }
            if matches(quote.delimiter, at: end) {
                end += width
                return quote.maxLength.map { end - position <= $0 + 2 * width } ?? true ? end : nil
            }
            if scalars[end] == "\n", !quote.multiline {
                return quote.maxLength == nil ? end : nil
            }
            end += 1
        }
        return quote.maxLength == nil ? scalars.count : nil
    }

    /// A `key:` (or TOML `key =`) opening a line, in key-value languages.
    private func isLineKey() -> Bool {
        guard language.lineKeys, isWordStart(scalars[position]) || scalars[position] == "-" else { return false }
        var start = position - 1
        while start >= 0, scalars[start] == " " || scalars[start] == "\t" { start -= 1 }
        guard start < 0 || scalars[start] == "\n" || (scalars[start] == "-" && language.id == "yaml") else { return false }
        var end = position
        while end < scalars.count, isWordCharacter(scalars[end]) || "-.".unicodeScalars.contains(scalars[end]) {
            end += 1
        }
        var separator = end
        while separator < scalars.count, scalars[separator] == " " { separator += 1 }
        return separator < scalars.count && (scalars[separator] == ":" || scalars[separator] == "=") && end > position
    }

    private mutating func emitLineKey() {
        var end = position
        while end < scalars.count, isWordCharacter(scalars[end]) || "-.".unicodeScalars.contains(scalars[end]) {
            end += 1
        }
        emit(until: end, .tag)
    }

    private func numberEnd() -> Int {
        var end = position + 1
        while end < scalars.count {
            let scalar = scalars[end]
            if isWordCharacter(scalar) || scalar == "." && end + 1 < scalars.count && isDigit(scalars[end + 1]) {
                end += 1
            } else {
                break
            }
        }
        return end
    }

    private func variableEnd() -> Int {
        if scalars[position + 1] == "{" {
            var end = position + 2
            while end < scalars.count, scalars[end] != "}", scalars[end] != "\n" { end += 1 }
            return min(end + 1, scalars.count)
        }
        return wordEnd(from: position + 1)
    }

    // MARK: Markup

    private mutating func scanMarkup() {
        while position < scalars.count {
            if matches("<!--", at: position) {
                var end = position + 4
                while end < scalars.count, !matches("-->", at: end) { end += 1 }
                emit(until: min(end + 3, scalars.count), .comment)
            } else if scalars[position] == "<", position + 1 < scalars.count,
                isWordStart(scalars[position + 1]) || "/!?".unicodeScalars.contains(scalars[position + 1])
            {
                var end = position + 1
                while end < scalars.count, "/!?".unicodeScalars.contains(scalars[end]) { end += 1 }
                emit(until: end, .punctuation)
                emit(until: tagNameEnd(), .tag)
                isInTag = true
            } else if isInTag, scalars[position] == ">" || matches("/>", at: position) {
                emit(until: position + (scalars[position] == ">" ? 1 : 2), .punctuation)
                isInTag = false
            } else if isInTag, scalars[position] == "\"" || scalars[position] == "'" {
                let quote = CodeLanguage.Quote(delimiter: String(scalars[position]), escapes: false, multiline: true)
                emit(until: quoteEnd(quote) ?? scalars.count, .string)
            } else if isInTag, isWordStart(scalars[position]) {
                emit(until: tagNameEnd(), .variable)
            } else if scalars[position] == "&" {
                var end = position + 1
                while end < scalars.count, end - position < 10, scalars[end] != ";", !isSpace(scalars[end]) { end += 1 }
                if end < scalars.count, scalars[end] == ";" {
                    emit(until: end + 1, .constant)
                } else {
                    position += 1
                }
            } else {
                position += 1
            }
        }
    }

    private func tagNameEnd() -> Int {
        var end = position
        while end < scalars.count, isWordCharacter(scalars[end]) || "-:.".unicodeScalars.contains(scalars[end]) {
            end += 1
        }
        return end
    }

    // MARK: Diff

    private mutating func scanDiff() {
        while position < scalars.count {
            let end = lineEnd(from: position)
            let role: CodeTokenRole? =
                if matches("+++", at: position) || matches("---", at: position) || matches("diff ", at: position)
                    || matches("index ", at: position)
                {
                    .comment
                } else if matches("@@", at: position) {
                    .keyword
                } else if scalars[position] == "+" {
                    .insertedForeground
                } else if scalars[position] == "-" {
                    .deletedForeground
                } else {
                    nil
                }
            if let role, end > position {
                emit(until: end, role)
            }
            position = end < scalars.count ? end + 1 : end
        }
    }

    // MARK: Emitting

    /// Ends the plain run at `position`, then emits `position..<end` in `role`.
    private mutating func emit(until end: Int, _ role: CodeTokenRole) {
        flushPlain()
        guard end > position else { return }
        segments.append(CodeSegment(String(String.UnicodeScalarView(scalars[position..<end])), role))
        position = end
        plainStart = end
    }

    private mutating func flushPlain() {
        guard position > plainStart else {
            plainStart = position
            return
        }
        segments.append(CodeSegment(String(String.UnicodeScalarView(scalars[plainStart..<position])), .foreground))
        plainStart = position
    }

    // MARK: Characters

    private var next: Unicode.Scalar {
        position + 1 < scalars.count ? scalars[position + 1] : " "
    }

    private func matches(_ text: String, at index: Int) -> Bool {
        var cursor = index
        for scalar in text.unicodeScalars {
            guard cursor < scalars.count, scalars[cursor] == scalar else { return false }
            cursor += 1
        }
        return true
    }

    private func lineEnd(from index: Int) -> Int {
        var end = index
        while end < scalars.count, scalars[end] != "\n" { end += 1 }
        return end
    }

    private func wordEnd(from index: Int) -> Int {
        var end = index
        while end < scalars.count, isWordCharacter(scalars[end]) { end += 1 }
        // Ruby's `defined?` and Swift's `try?`/`as!` read as one word.
        if end < scalars.count, "?!".unicodeScalars.contains(scalars[end]),
            language.keywords.contains(String(String.UnicodeScalarView(scalars[position..<end + 1])))
        {
            end += 1
        }
        return end
    }

    private func isFollowed(by scalar: Unicode.Scalar, at index: Int) -> Bool {
        index < scalars.count && scalars[index] == scalar
    }

    private func isFollowedByColon(_ index: Int) -> Bool {
        var cursor = index
        while cursor < scalars.count, scalars[cursor] == " " { cursor += 1 }
        return cursor < scalars.count && scalars[cursor] == ":"
    }

    private func isWordStart(_ scalar: Unicode.Scalar) -> Bool {
        scalar == "_" || scalar.properties.isAlphabetic
    }

    private func isWordCharacter(_ scalar: Unicode.Scalar) -> Bool {
        scalar == "_" || scalar.properties.isAlphabetic || isDigit(scalar)
    }

    private func isDigit(_ scalar: Unicode.Scalar) -> Bool {
        ("0"..."9").contains(scalar)
    }

    private func isSpace(_ scalar: Unicode.Scalar) -> Bool {
        scalar == " " || scalar == "\t" || scalar == "\n"
    }

    private func isOperator(_ scalar: Unicode.Scalar) -> Bool {
        "+-*/%=&|^!<>?~".unicodeScalars.contains(scalar)
    }
}
