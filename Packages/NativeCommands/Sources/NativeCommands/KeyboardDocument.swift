import Foundation

/// The default shortcuts `docs/keyboard.md` lists: every table row with a `Command` column names
/// its command ids in backticks, and its first column has the keys.
///
///     | Keys | Action | Menu | Command |
///     | ⌘[ / ⌘] | Back / forward | Go | `go.back` / `go.forward` |
///     | ⌘1 – ⌘9 | Go to the Nth session | Session | `session.select1` – `session.select9` |
///     | | Close the terminal tab | View | `terminal.closeTab` |
///
/// Keys and ids pair up in order (" / " separates alternatives); a " – " range pairs each digit.
public enum KeyboardDocument {
    public struct Entry: Equatable, Sendable {
        public var command: CommandID
        /// nil for a command the doc lists without a default shortcut.
        public var shortcut: KeyShortcut?
        public var line: Int
    }

    public struct ParseError: Error, Equatable, CustomStringConvertible {
        public var line: Int
        public var problem: String

        public var description: String { "docs/keyboard.md line \(line): \(problem)" }
    }

    public static func entries(in markdown: String) throws(ParseError) -> [Entry] {
        var entries: [Entry] = []
        var commandColumn: Int?
        for (offset, line) in markdown.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            let number = offset + 1
            guard line.hasPrefix("|") else {
                commandColumn = nil
                continue
            }
            let cells = Self.cells(of: line)
            if cells.allSatisfy({ $0.allSatisfy { $0 == "-" || $0 == ":" } }) {
                continue
            }
            guard let column = commandColumn else {
                // A table's first row is its header.
                commandColumn = cells.firstIndex(of: "Command") ?? -1
                continue
            }
            guard column >= 0, cells.indices.contains(column), !cells[column].isEmpty else { continue }
            entries += try Self.entries(keys: cells[0], commands: cells[column], line: number)
        }
        return entries
    }

    private static func entries(keys: String, commands: String, line: Int) throws(ParseError) -> [Entry] {
        let names = Self.backticked(commands)
        guard !names.isEmpty else {
            throw ParseError(line: line, problem: "the Command column has no `id`")
        }
        if keys.isEmpty {
            return names.map { Entry(command: CommandID($0), shortcut: nil, line: line) }
        }
        if commands.contains(" – ") {
            return try Self.range(keys: keys, ids: names, line: line)
        }
        let shortcuts = keys.components(separatedBy: " / ")
        guard shortcuts.count == names.count else {
            throw ParseError(line: line, problem: "\(shortcuts.count) keys for \(names.count) commands")
        }
        return try zip(names, shortcuts).map { (name, text) throws(ParseError) in
            guard let shortcut = KeyShortcut(text) else {
                throw ParseError(line: line, problem: "can't read \(text) as a shortcut")
            }
            return Entry(command: CommandID(name), shortcut: shortcut, line: line)
        }
    }

    /// "⌘1 – ⌘9" with "`session.select1` – `session.select9`": one entry per digit.
    private static func range(keys: String, ids: [String], line: Int) throws(ParseError) -> [Entry] {
        let bounds = keys.components(separatedBy: " – ")
        guard bounds.count == 2, ids.count == 2,
            let first = KeyShortcut(bounds[0]), let last = KeyShortcut(bounds[1]),
            case .character(let low) = first.key, case .character(let high) = last.key,
            let lowDigit = low.wholeNumberValue, let highDigit = high.wholeNumberValue, lowDigit <= highDigit,
            first.modifiers == last.modifiers,
            ids[0].hasSuffix(String(lowDigit)), ids[1].hasSuffix(String(highDigit)),
            ids[0].dropLast() == ids[1].dropLast()
        else {
            throw ParseError(line: line, problem: "a range needs digit keys and ids ending in the same digits")
        }
        let stem = ids[0].dropLast()
        return (lowDigit...highDigit).map { digit in
            Entry(
                command: CommandID("\(stem)\(digit)"),
                shortcut: KeyShortcut(String(digit)).map { KeyShortcut($0.key, modifiers: first.modifiers) },
                line: line)
        }
    }

    private static func backticked(_ text: String) -> [String] {
        text.split(separator: "`", omittingEmptySubsequences: false).enumerated()
            .filter { !$0.offset.isMultiple(of: 2) }
            .map { String($0.element) }
    }

    private static func cells(of line: Substring) -> [String] {
        var cells = line.split(separator: "|", omittingEmptySubsequences: false).map {
            $0.trimmingCharacters(in: .whitespaces)
        }
        // The leading and trailing pipes leave an empty cell at each end.
        if cells.first == "" { cells.removeFirst() }
        if cells.last == "" { cells.removeLast() }
        return cells
    }
}
