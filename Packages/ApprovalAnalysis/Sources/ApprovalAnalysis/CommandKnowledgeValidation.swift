import Foundation

enum CommandKnowledgeValidation {
    struct Invalid: Error {
        let message: String
        init(_ message: String) { self.message = message }
    }

    static func message(_ error: any Error) -> String {
        if let invalid = error as? Invalid { return invalid.message }
        if let error = error as? DecodingError {
            switch error {
            case .keyNotFound(let key, _): return "missing field \(key.stringValue)"
            case .typeMismatch(_, let context), .valueNotFound(_, let context), .dataCorrupted(let context):
                return "invalid field \(context.codingPath.map(\.stringValue).joined(separator: "."))"
            @unknown default: break
            }
        }
        return "invalid entry"
    }

    static func object(_ raw: Any, keys: Set<String>) throws -> [String: Any] {
        guard let value = raw as? [String: Any], Set(value.keys).isSubset(of: keys) else {
            throw Invalid("unexpected fields or wrong object type")
        }
        return value
    }

    static func decode<T: Decodable>(_ type: T.Type, _ raw: Any) throws -> T {
        try JSONDecoder().decode(type, from: JSONSerialization.data(withJSONObject: raw))
    }

    static func program(_ raw: Any) throws -> CommandKnowledge.Program {
        let object = try object(raw, keys: ["executables", "commands"])
        guard let commands = object["commands"] as? [Any], (1...128).contains(commands.count) else {
            throw Invalid("commands must contain 1 to 128 entries")
        }
        for command in commands {
            let fields = try self.object(
                command,
                keys: [
                    "words", "summary", "consequence", "destructive", "options", "operands",
                    "optionsBeforeOperands", "shortClusters", "noSuggestionWithOptions",
                    "noSuggestionWithOperandPrefixes",
                ])
            _ = try self.object(fields["operands"] as Any, keys: ["minimum", "maximum", "summary", "paths"])
            guard let options = fields["options"] as? [Any], options.count <= 128 else {
                throw Invalid("options must be an array with at most 128 entries")
            }
            for option in options {
                _ = try self.object(
                    option, keys: ["names", "summary", "destructive", "value", "replacement", "alternative"])
            }
        }
        let program = try decode(CommandKnowledge.Program.self, raw)
        guard (1...16).contains(program.executables.count),
            Set(program.executables).count == program.executables.count,
            program.executables.allSatisfy({ executable in
                !executable.isEmpty && executable != "/" && executable.count <= 256 && !executable.hasPrefix("-")
                    && executable.split(separator: "/", omittingEmptySubsequences: false)
                        .enumerated().allSatisfy { index, part in
                            (index == 0 && part.isEmpty) || identifier(String(part))
                        }
                    && !executable.contains("..")
            })
        else { throw Invalid("executables must be unique literal names or paths") }
        guard Set(program.commands.map(\.words)).count == program.commands.count else {
            throw Invalid("duplicate command words")
        }
        for rule in program.commands {
            guard rule.words.count <= 4, rule.words.allSatisfy(identifier),
                text(rule.summary, placeholders: ["count"]), text(rule.consequence, placeholders: []),
                rule.operands.minimum >= 0, rule.operands.minimum <= 128,
                rule.operands.maximum.map({ $0 >= rule.operands.minimum && $0 <= 128 }) ?? true,
                text(rule.operands.summary, placeholders: ["value", "scope", "location"])
            else { throw Invalid("invalid command words, text template, or operand bounds") }
            let names = rule.options.flatMap(\.names)
            guard Set(names).count == names.count else { throw Invalid("duplicate option names") }
            guard (rule.noSuggestionWithOptions ?? []).allSatisfy({ names.contains($0) }),
                (rule.noSuggestionWithOperandPrefixes ?? []).allSatisfy({ !$0.isEmpty && $0.count <= 64 })
            else { throw Invalid("invalid suggestion blockers") }
            for option in rule.options {
                guard !option.names.isEmpty,
                    option.names.allSatisfy({ $0.hasPrefix("-") && $0 != "--" && identifier(String($0.dropFirst())) }),
                    text(option.summary, placeholders: []),
                    option.alternative.map({ text($0, placeholders: []) }) ?? true
                else { throw Invalid("invalid option names, value mode, or text") }
                if let replacement = option.replacement {
                    guard option.value == .none, option.alternative != nil,
                        rule.options.contains(where: {
                            $0.names.contains(replacement) && $0.value == .none && $0.replacement == nil
                        })
                    else {
                        throw Invalid("replacement must name an existing valueless option and explain the alternative")
                    }
                } else if option.alternative != nil {
                    throw Invalid("alternative needs a replacement")
                }
            }
        }
        return program
    }

    static func location(_ raw: Any) throws -> CommandKnowledge.Location {
        _ = try object(raw, keys: ["kind", "path", "summary"])
        let location = try decode(CommandKnowledge.Location.self, raw)
        guard !location.path.isEmpty, location.path.count <= 256, !location.path.contains(".."),
            !location.path.hasPrefix("/"), !location.path.hasSuffix("/"),
            location.path.split(separator: "/").allSatisfy({ identifier(String($0)) }),
            location.kind != .component || !location.path.contains("/"),
            text(location.summary, placeholders: [])
        else { throw Invalid("invalid location kind, path, or summary") }
        return location
    }

    static func identifier(_ text: String) -> Bool {
        !text.isEmpty
            && text.utf8.allSatisfy {
                (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0)
                    || [45, 46, 95, 43].contains($0)
            }
    }

    static func text(_ text: String, placeholders: Set<String>) -> Bool {
        guard !text.isEmpty, text.count <= 300,
            !text.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
        else { return false }
        var remaining = text
        for placeholder in placeholders { remaining = remaining.replacingOccurrences(of: "{\(placeholder)}", with: "") }
        return !remaining.contains("{") && !remaining.contains("}")
    }
}
