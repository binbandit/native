import Foundation

/// Quotes command lines the way a POSIX shell reads them, so a command Native shows can be pasted
/// into a terminal and run as is.
public enum ShellQuoting {
    public static func commandLine(_ words: [String]) -> String {
        words.map(quote).joined(separator: " ")
    }

    public static func quote(_ word: String) -> String {
        guard !word.isEmpty else { return "''" }
        if word.unicodeScalars.allSatisfy(isSafe) { return word }
        return "'" + word.replacingOccurrences(of: "'", with: #"'\''"#) + "'"
    }

    /// Splits a command line into words the way a POSIX shell does: whitespace separates them,
    /// single quotes keep everything, double quotes keep all but `\"` and `\\`, and a backslash
    /// escapes the next character. Nil when a quote is left open. No expansion happens.
    public static func split(_ line: String) -> [String]? {
        var words: [String] = []
        var word = ""
        var inWord = false
        var quote: Character?
        var escaped = false
        for character in line {
            if escaped {
                word.append(character)
                escaped = false
            } else if let open = quote {
                if character == open {
                    quote = nil
                } else if open == "\"", character == "\\" {
                    escaped = true
                } else {
                    word.append(character)
                }
            } else if character == "'" || character == "\"" {
                quote = character
                inWord = true
            } else if character == "\\" {
                escaped = true
                inWord = true
            } else if character.isWhitespace {
                if inWord { words.append(word) }
                word = ""
                inWord = false
            } else {
                word.append(character)
                inWord = true
            }
        }
        guard quote == nil, !escaped else { return nil }
        if inWord { words.append(word) }
        return words
    }

    private static func isSafe(_ scalar: Unicode.Scalar) -> Bool {
        scalar.isASCII && (CharacterSet.alphanumerics.contains(scalar) || "_@%+=:,./-".unicodeScalars.contains(scalar))
    }
}
