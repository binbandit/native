import Foundation

/// Reads only display fields from os-release, without evaluating shell expressions.
enum HostLinuxReleaseInfo {
    static func systemName(
        fallback: String = ProcessInfo.processInfo.operatingSystemVersionString,
        readFile: (String) throws -> String = { try String(contentsOfFile: $0, encoding: .utf8) }
    ) -> String {
        // A readable but empty or malformed /etc file still takes precedence over the vendor file.
        let contents = (try? readFile("/etc/os-release")) ?? (try? readFile("/usr/lib/os-release"))
        return contents.flatMap(displayName) ?? fallback
    }

    static func displayName(_ contents: String) -> String? {
        var fields: [String: String] = [:]
        for line in contents.split(whereSeparator: \.isNewline) {
            let line = line.trimmingCharacters(in: .whitespaces)
            guard !line.hasPrefix("#"), let separator = line.firstIndex(of: "=") else { continue }
            let key = line[..<separator].trimmingCharacters(in: .whitespaces)
            guard ["PRETTY_NAME", "NAME", "VERSION"].contains(key),
                let value = decode(String(line[line.index(after: separator)...]))
            else { continue }
            fields[key] = value.trimmingCharacters(in: .whitespaces)
        }
        if let pretty = fields["PRETTY_NAME"], !pretty.isEmpty { return pretty }
        guard let name = fields["NAME"], !name.isEmpty else { return nil }
        return [name, fields["VERSION"] ?? ""].filter { !$0.isEmpty }.joined(separator: " ")
    }

    private static func decode(_ raw: String) -> String? {
        let value = raw.trimmingCharacters(in: .whitespaces)
        var characters = value.makeIterator()
        guard let first = characters.next() else { return "" }
        let quote: Character? = first == "\"" || first == "'" ? first : nil
        var current: Character? = quote == nil ? first : characters.next()
        var result = ""
        while let character = current {
            if let quote, character == quote {
                // os-release does not support concatenating quoted strings or trailing expressions.
                return characters.next() == nil ? result : nil
            }
            if character == "\\", quote != "'" {
                guard let escaped = characters.next() else { return nil }
                // Inside double quotes, shell escaping leaves other backslashes literal.
                if quote == "\"", !["$", "`", "\"", "\\"].contains(escaped) { result.append("\\") }
                result.append(escaped)
            } else {
                if quote == nil, character.isWhitespace || character == "\"" || character == "'" { return nil }
                result.append(character)
            }
            current = characters.next()
        }
        return quote == nil ? result : nil
    }
}
