import Foundation

/// Folding removes a whole call, so partial JavaScript parsing cannot establish its target.
/// Accept only a flat literal argument object; computed values keep their original row.
enum CodeModePollingInput {
    static func session(in arguments: Substring) -> String? {
        let text = arguments.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.hasPrefix("("), text.hasSuffix(")") else { return nil }
        let object = text.dropFirst().dropLast().trimmingCharacters(in: .whitespacesAndNewlines)
        guard object.hasPrefix("{"), object.hasSuffix("}") else { return nil }
        var rest = String(object.dropFirst().dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
        var fields: [String: String] = [:]
        // Anchoring each property and its delimiter rejects numeric/string prefixes of expressions,
        // spreads, shorthand and duplicate keys rather than guessing which value wins at runtime.
        let property =
            #"^\s*(session_id|chars|yield_time_ms|max_output_tokens|"(?:session_id|chars|yield_time_ms|max_output_tokens)"|'(?:session_id|chars|yield_time_ms|max_output_tokens)')\s*:\s*([0-9]+|"(?:[^"\\]|\\.)*"|'(?:[^'\\]|\\.)*'|`[^`$\\]*`)\s*(,|$)"#
        guard let regex = try? NSRegularExpression(pattern: property) else { return nil }
        while !rest.isEmpty {
            guard let match = regex.firstMatch(in: rest, range: NSRange(rest.startIndex..., in: rest)),
                let keyRange = Range(match.range(at: 1), in: rest),
                let valueRange = Range(match.range(at: 2), in: rest),
                let wholeRange = Range(match.range, in: rest)
            else { return nil }
            let key = String(rest[keyRange]).trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            guard fields[key] == nil else { return nil }
            fields[key] = String(rest[valueRange])
            rest = String(rest[wholeRange.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard let literal = fields["session_id"] else { return nil }
        let session = literal.trimmingCharacters(in: CharacterSet(charactersIn: "\"'`"))
        guard !session.isEmpty, session.allSatisfy({ $0.isASCII && $0.isNumber }),
            fields["chars"].map({ ["\"\"", "''", "``"].contains($0) }) ?? true
        else { return nil }
        return session
    }
}
