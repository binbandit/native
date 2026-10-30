import Foundation

/// What a shell command is for, when it's one of the few ways agents read or search through the
/// shell: `cat greet.py`, `sed -n '1,80p' Sources/A.swift`, `rg -n 'playful' native | head -80`.
/// Those read as the step they are ("Read greet.py", "Searched for "playful" in native"), the same
/// as a dedicated tool would say it. Anything else, or anything it can't be sure of (a redirect, a
/// substitution, a chain), stays a command.
enum ToolCommandIntent: Equatable {
    case read(paths: [String], lines: String?)
    case search(pattern: String, path: String?)
    case list(path: String?)

    init?(_ command: String) {
        // `cat a && cat b` reads both.
        if let parts = Self.split(command, at: "&&"), parts.count > 1 {
            var paths: [String] = []
            for part in parts {
                guard case .read(let more, nil)? = ToolCommandIntent(part) else { return nil }
                paths += more
            }
            self = .read(paths: paths, lines: nil)
            return
        }
        guard var stages = Self.stages(command) else { return nil }
        // `nl -ba F | sed -n '1,80p'`: numbered lines, then a range of them.
        if stages.count == 2, let numbered = Self.words(stages[0]), numbered.first == "nl",
            let path = numbered.dropFirst().last(where: { !$0.hasPrefix("-") }),
            let range = Self.words(stages[1]).flatMap(Self.sedRange)
        {
            self = .read(paths: [path], lines: range)
            return
        }
        // Output trimmed by a pager is still the same read or search.
        while stages.count > 1, let last = stages.last, Self.isTrim(last) {
            stages.removeLast()
        }
        guard stages.count == 1, let words = Self.words(stages[0]), let program = words.first else { return nil }
        let arguments = Array(words.dropFirst())
        let operands = arguments.filter { !$0.hasPrefix("-") }
        switch program {
        case "cat" where !operands.isEmpty && operands.count == arguments.count:
            self = .read(paths: operands, lines: nil)
        case "head", "tail":
            guard let path = Self.lastOperand(arguments, valueFlags: ["-n", "-c"]) else { return nil }
            self = .read(paths: [path], lines: nil)
        case "sed":
            guard let range = Self.sedRange(words), let path = operands.last, operands.count == 2 else { return nil }
            self = .read(paths: [path], lines: range)
        case "rg" where arguments.contains("--files"):
            self = .list(path: operands.first)
        case "rg", "grep":
            let valueFlags: Set<String> = ["-g", "--glob", "-t", "--type", "-A", "-B", "-C", "-m", "--max-count"]
            var patterns: [String] = []
            var remaining: [String] = []
            var index = 0
            while index < arguments.count {
                let argument = arguments[index]
                if argument == "--" {
                    remaining += arguments[index...]
                    break
                } else if valueFlags.contains(argument) {
                    guard index + 1 < arguments.count else { return nil }
                    remaining += arguments[index...index + 1]
                    index += 2
                    continue
                } else if argument == "-e" || argument == "--regexp" {
                    index += 1
                    guard index < arguments.count else { return nil }
                    patterns.append(arguments[index])
                } else if argument.hasPrefix("--regexp=") {
                    patterns.append(String(argument.dropFirst("--regexp=".count)))
                } else if argument.hasPrefix("-e"), argument.count > 2 {
                    patterns.append(String(argument.dropFirst(2)))
                } else {
                    remaining.append(argument)
                }
                index += 1
            }
            let values = Self.operands(remaining, valueFlags: valueFlags)
            if patterns.isEmpty {
                guard let pattern = values.first, values.count <= 2 else { return nil }
                self = .search(pattern: pattern, path: values.dropFirst().first)
            } else {
                // Multiple expressions cannot be represented faithfully by a single query.
                guard patterns.count == 1, values.count <= 1 else { return nil }
                self = .search(pattern: patterns[0], path: values.first)
            }
        case "ls":
            guard operands.count <= 1 else { return nil }
            self = .list(path: operands.first)
        default:
            return nil
        }
    }

    /// `command` split at `separator` outside quotes, or nil when it has none.
    private static func split(_ command: String, at separator: String) -> [String]? {
        var parts: [String] = []
        var current = ""
        var quote: Character?
        var rest = Substring(command)
        while let character = rest.first {
            if quote == nil, rest.hasPrefix(separator) {
                parts.append(current.trimmingCharacters(in: .whitespaces))
                current = ""
                rest = rest.dropFirst(separator.count)
                continue
            }
            if let open = quote {
                if character == open { quote = nil }
            } else if character == "'" || character == "\"" {
                quote = character
            }
            current.append(character)
            rest = rest.dropFirst()
        }
        guard !parts.isEmpty else { return nil }
        parts.append(current.trimmingCharacters(in: .whitespaces))
        return parts
    }

    /// The stages of a pipeline, split at pipes outside quotes; nil for `||`.
    private static func stages(_ command: String) -> [String]? {
        var stages: [String] = []
        var current = ""
        var quote: Character?
        var previous: Character?
        for character in command {
            if let open = quote {
                if character == open { quote = nil }
                current.append(character)
            } else if character == "'" || character == "\"" {
                quote = character
                current.append(character)
            } else if character == "|" {
                if previous == "|" { return nil }
                stages.append(current.trimmingCharacters(in: .whitespaces))
                current = ""
            } else {
                current.append(character)
            }
            previous = character
        }
        stages.append(current.trimmingCharacters(in: .whitespaces))
        return stages
    }

    /// `head -80`, `head -n 80`, `sed -n '1,80p'`: a stage that only trims what came before.
    private static func isTrim(_ stage: String) -> Bool {
        guard let words = words(stage), let program = words.first else { return false }
        switch program {
        case "head", "tail": return words.dropFirst().allSatisfy { $0.hasPrefix("-") || Int($0) != nil }
        case "sed": return sedRange(words) != nil && words.count == 3
        default: return false
        }
    }

    /// `sed -n '10,59p'` is lines 10-59.
    private static func sedRange(_ words: [String]) -> String? {
        guard words.first == "sed", words.count >= 3, words[1] == "-n" else { return nil }
        let script = words[2]
        guard script.hasSuffix("p") else { return nil }
        let bounds = script.dropLast().split(separator: ",")
        guard (1...2).contains(bounds.count), bounds.allSatisfy({ Int($0) != nil }) else { return nil }
        return bounds.count == 2 ? "\(bounds[0])-\(bounds[1])" : String(bounds[0])
    }

    private static func operands(_ arguments: [String], valueFlags: Set<String>) -> [String] {
        var operands: [String] = []
        var skipsNext = false
        for argument in arguments {
            if skipsNext {
                skipsNext = false
            } else if valueFlags.contains(argument) {
                skipsNext = true
            } else if !argument.hasPrefix("-") {
                operands.append(argument)
            }
        }
        return operands
    }

    private static func lastOperand(_ arguments: [String], valueFlags: Set<String>) -> String? {
        let operands = operands(arguments, valueFlags: valueFlags)
        return operands.count == 1 ? operands[0] : nil
    }

    /// The words of a simple command, quotes removed; nil for anything with shell syntax in it
    /// (a redirect, a substitution, a variable, a chain), which this won't guess at.
    static func words(_ stage: String) -> [String]? {
        var words: [String] = []
        var current = ""
        var quote: Character?
        var hasWord = false
        for character in stage {
            if let open = quote {
                if character == open { quote = nil } else { current.append(character) }
            } else if character == "'" || character == "\"" {
                quote = character
                hasWord = true
            } else if character == " " || character == "\t" {
                if hasWord { words.append(current) }
                current = ""
                hasWord = false
            } else if "<>;&$`(){}\n".contains(character) {
                return nil
            } else {
                current.append(character)
                hasWord = true
            }
        }
        guard quote == nil else { return nil }
        if hasWord { words.append(current) }
        return words.isEmpty ? nil : words
    }
}
