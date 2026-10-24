/// Accepts only literal argv words. Unsupported shell syntax falls back as a whole, so a familiar
/// prefix never lends reassuring annotations to an unexamined suffix.
struct ApprovalCommandWords {
    struct Token {
        let value: String
        let range: Range<Int>
        let expandsHome: Bool
    }
    let tokens: [Token]

    init?(_ command: String) {
        let chars = Array(command)
        var result: [Token] = []
        var index = 0
        while index < chars.count {
            while index < chars.count, chars[index] == " " || chars[index] == "\t" { index += 1 }
            guard index < chars.count else { break }
            let start = index
            var value = ""
            var quote: Character?
            while index < chars.count {
                let char = chars[index]
                if char == "\n" || char == "\r" || char == "\0" { return nil }
                if quote == nil, char == " " || char == "\t" { break }
                if char == "'" || char == "\"" {
                    if quote == char { quote = nil } else if quote == nil { quote = char } else { value.append(char) }
                } else {
                    // Even quoted substitutions and escaped syntax are intentionally unsupported.
                    guard !"$`\\".contains(char), quote != nil || !";&|<>()*?[]{}#".contains(char) else { return nil }
                    value.append(char)
                }
                index += 1
            }
            guard quote == nil, !value.isEmpty else { return nil }
            result.append(Token(value: value, range: start..<index, expandsHome: chars[start] == "~"))
        }
        guard !result.isEmpty else { return nil }
        tokens = result
    }
}
