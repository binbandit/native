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

    private static func isSafe(_ scalar: Unicode.Scalar) -> Bool {
        scalar.isASCII && (CharacterSet.alphanumerics.contains(scalar) || "_@%+=:,./-".unicodeScalars.contains(scalar))
    }
}
