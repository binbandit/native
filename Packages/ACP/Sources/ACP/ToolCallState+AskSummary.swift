import Foundation

extension ToolCallState {
    /// A short sentence for navigation, never an approval control. The full command remains in
    /// the permission card. Only plain command words are shortened; shell syntax stays literal.
    public var askSummary: String {
        if kind == .switchMode { return "Review the plan: \(title)" }
        guard let command = shellCommand else { return "Allow \(title)?" }
        let words = command.split(whereSeparator: \.isWhitespace)
        guard let first = words.first,
            first.allSatisfy({ $0.isLetter || $0.isNumber || "_./-".contains($0) })
        else { return "Allow \(title)?" }
        let binary = (String(first) as NSString).lastPathComponent
        var short = binary
        // An option or a shell operator is not a subcommand.
        if words.count > 1, words[1].first?.isLetter == true,
            words[1].allSatisfy({ $0.isLetter || $0.isNumber || "_-".contains($0) })
        {
            short += " \(words[1])"
        }
        return "Allow `\(short)`?"
    }
}
