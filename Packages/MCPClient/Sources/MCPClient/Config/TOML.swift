import Foundation

/// A TOML value. Dates and times are kept as the text they were written as.
public enum TOMLValue: Hashable, Sendable {
    case string(String)
    case integer(Int)
    case float(Double)
    case bool(Bool)
    case dateTime(String)
    case array([TOMLValue])
    case table([String: TOMLValue])

    public subscript(key: String) -> TOMLValue? {
        guard case .table(let table) = self else { return nil }
        return table[key]
    }

    public var stringValue: String? {
        guard case .string(let string) = self else { return nil }
        return string
    }

    public var boolValue: Bool? {
        guard case .bool(let bool) = self else { return nil }
        return bool
    }

    public var tableValue: [String: TOMLValue]? {
        guard case .table(let table) = self else { return nil }
        return table
    }

    public var arrayValue: [TOMLValue]? {
        guard case .array(let array) = self else { return nil }
        return array
    }

    /// Strings, numbers and booleans as text, the way configuration values are meant.
    public var scalarText: String? {
        switch self {
        case .string(let string), .dateTime(let string): string
        case .integer(let integer): String(integer)
        case .float(let float): String(float)
        case .bool(let bool): String(bool)
        case .array, .table: nil
        }
    }
}

public struct TOMLError: Error, Hashable, Sendable, CustomStringConvertible {
    public var line: Int
    public var message: String

    public init(line: Int, message: String) {
        self.line = line
        self.message = message
    }

    public var description: String { "Line \(line): \(message)" }
}

/// A TOML 1.0 reader, for configuration files like Codex's `config.toml`.
public enum TOML {
    public static func parse(_ text: String) throws(TOMLError) -> [String: TOMLValue] {
        var parser = TOMLParser(text)
        return try parser.document()
    }
}

/// Tables are built as references so a header can reopen one and dotted keys can reach into it.
private final class TableBuilder {
    enum Entry {
        case value(TOMLValue)
        case table(TableBuilder)
        case tables([TableBuilder])
    }

    var entries: [String: Entry] = [:]
    /// Created implicitly by a dotted key or a header's parents, so a later header may still define it.
    var isImplicit = false

    var value: TOMLValue {
        .table(entries.mapValues { entry in
            switch entry {
            case .value(let value): value
            case .table(let table): table.value
            case .tables(let tables): .array(tables.map(\.value))
            }
        })
    }
}

private struct TOMLParser {
    private let scalars: [Unicode.Scalar]
    private var index = 0
    private var line = 1

    init(_ text: String) {
        scalars = Array(text.unicodeScalars)
    }

    mutating func document() throws(TOMLError) -> [String: TOMLValue] {
        let root = TableBuilder()
        var current = root
        while true {
            skipBlank(newlines: true)
            guard let scalar = peek() else { break }
            if scalar == "[" {
                if peek(1) == "[" {
                    index += 2
                    let path = try key()
                    try expect("]")
                    try expect("]")
                    current = try appendTable(at: path, in: root)
                } else {
                    index += 1
                    let path = try key()
                    try expect("]")
                    current = try table(at: path, in: root, header: true)
                }
            } else {
                let path = try key()
                skipBlank(newlines: false)
                try expect("=")
                skipBlank(newlines: false)
                let parsed = try value()
                try assign(parsed, to: path, in: current)
            }
            skipBlank(newlines: false)
            guard let next = peek() else { break }
            guard next == "\n" || next == "\r" else { throw failure("Expected the end of the line.") }
        }
        guard case .table(let table) = root.value else { return [:] }
        return table
    }

    // MARK: - Tables

    private func table(at path: [String], in root: TableBuilder, header: Bool) throws(TOMLError) -> TableBuilder {
        var table = root
        for (offset, part) in path.enumerated() {
            let isLast = offset == path.count - 1
            switch table.entries[part] {
            case nil:
                let child = TableBuilder()
                child.isImplicit = !(header && isLast)
                table.entries[part] = .table(child)
                table = child
            case .table(let child)?:
                if header && isLast {
                    guard child.isImplicit else { throw failure("The table [\(path.joined(separator: "."))] is defined twice.") }
                    child.isImplicit = false
                }
                table = child
            case .tables(let tables)?:
                guard let last = tables.last else { throw failure("Empty array of tables.") }
                table = last
            case .value?:
                throw failure("\"\(part)\" is already a value, not a table.")
            }
        }
        return table
    }

    private func appendTable(at path: [String], in root: TableBuilder) throws(TOMLError) -> TableBuilder {
        let parent = try table(at: Array(path.dropLast()), in: root, header: false)
        guard let name = path.last else { throw failure("Missing table name.") }
        let table = TableBuilder()
        switch parent.entries[name] {
        case nil: parent.entries[name] = .tables([table])
        case .tables(let tables)?: parent.entries[name] = .tables(tables + [table])
        default: throw failure("\"\(name)\" isn't an array of tables.")
        }
        return table
    }

    private func assign(_ value: TOMLValue, to path: [String], in table: TableBuilder) throws(TOMLError) {
        let parent = try self.table(at: Array(path.dropLast()), in: table, header: false)
        guard let name = path.last else { throw failure("Missing key.") }
        guard parent.entries[name] == nil else { throw failure("\"\(path.joined(separator: "."))\" is defined twice.") }
        parent.entries[name] = .value(value)
    }

    // MARK: - Keys

    /// A dotted key: bare or quoted parts separated by dots.
    private mutating func key() throws(TOMLError) -> [String] {
        var parts: [String] = []
        repeat {
            skipBlank(newlines: false)
            switch peek() {
            case "\"":
                index += 1
                parts.append(try basicString())
            case "'":
                index += 1
                parts.append(try literalString())
            default:
                let start = index
                while let scalar = peek(), Self.isBareKey(scalar) { index += 1 }
                guard index > start else { throw failure("Expected a key.") }
                parts.append(String(String.UnicodeScalarView(scalars[start..<index])))
            }
            skipBlank(newlines: false)
        } while consume(".")
        return parts
    }

    private static func isBareKey(_ scalar: Unicode.Scalar) -> Bool {
        (scalar >= "a" && scalar <= "z") || (scalar >= "A" && scalar <= "Z") || (scalar >= "0" && scalar <= "9") || scalar == "_" || scalar == "-"
    }

    // MARK: - Values

    private mutating func value() throws(TOMLError) -> TOMLValue {
        switch peek() {
        case "\"":
            if peek(1) == "\"", peek(2) == "\"" {
                index += 3
                return .string(try multilineString(literal: false))
            }
            index += 1
            return .string(try basicString())
        case "'":
            if peek(1) == "'", peek(2) == "'" {
                index += 3
                return .string(try multilineString(literal: true))
            }
            index += 1
            return .string(try literalString())
        case "[":
            index += 1
            return try array()
        case "{":
            index += 1
            return try inlineTable()
        case nil:
            throw failure("Expected a value.")
        default:
            return try scalarValue()
        }
    }

    private mutating func array() throws(TOMLError) -> TOMLValue {
        var items: [TOMLValue] = []
        while true {
            skipBlank(newlines: true)
            if consume("]") { return .array(items) }
            items.append(try value())
            skipBlank(newlines: true)
            if consume(",") { continue }
            try expect("]")
            return .array(items)
        }
    }

    /// Inline tables, allowing TOML 1.1's newlines and trailing comma.
    private mutating func inlineTable() throws(TOMLError) -> TOMLValue {
        let table = TableBuilder()
        while true {
            skipBlank(newlines: true)
            if consume("}") { return table.value }
            let path = try key()
            try expect("=")
            skipBlank(newlines: false)
            try assign(try value(), to: path, in: table)
            skipBlank(newlines: true)
            if consume(",") { continue }
            try expect("}")
            return table.value
        }
    }

    private mutating func scalarValue() throws(TOMLError) -> TOMLValue {
        let start = index
        while let scalar = peek(), !"\n\r,]}#".unicodeScalars.contains(scalar) {
            // A date and time may be separated by one space: `1979-05-27 07:32:00`.
            if scalar == " " {
                guard let next = peek(1), next >= "0", next <= "9", scalars[start..<index].contains("-") else { break }
            } else if scalar == "\t" {
                break
            }
            index += 1
        }
        let token = String(String.UnicodeScalarView(scalars[start..<index])).trimmingCharacters(in: .whitespaces)
        switch token {
        case "true": return .bool(true)
        case "false": return .bool(false)
        case "inf", "+inf": return .float(.infinity)
        case "-inf": return .float(-.infinity)
        case "nan", "+nan", "-nan": return .float(.nan)
        default: break
        }
        let digits = token.replacingOccurrences(of: "_", with: "")
        for (prefix, radix) in [("0x", 16), ("0o", 8), ("0b", 2)] where digits.hasPrefix(prefix) {
            guard let value = Int(digits.dropFirst(2), radix: radix) else { break }
            return .integer(value)
        }
        if let integer = Int(digits) { return .integer(integer) }
        if digits.contains(where: { $0 == "." || $0 == "e" || $0 == "E" }), let float = Double(digits) { return .float(float) }
        if token.first?.isNumber == true, token.contains("-") || token.contains(":") { return .dateTime(token) }
        throw failure("\"\(token)\" isn't a value.")
    }

    // MARK: - Strings

    private mutating func basicString() throws(TOMLError) -> String {
        var result = String.UnicodeScalarView()
        while let scalar = next() {
            switch scalar {
            case "\"": return String(result)
            case "\\": result.append(contentsOf: try escape())
            case "\n": throw failure("Strings can't span lines; use \"\"\" for that.")
            default: result.append(scalar)
            }
        }
        throw failure("Unterminated string.")
    }

    private mutating func literalString() throws(TOMLError) -> String {
        var result = String.UnicodeScalarView()
        while let scalar = next() {
            switch scalar {
            case "'": return String(result)
            case "\n": throw failure("Strings can't span lines; use ''' for that.")
            default: result.append(scalar)
            }
        }
        throw failure("Unterminated string.")
    }

    private mutating func multilineString(literal: Bool) throws(TOMLError) -> String {
        let delimiter: Unicode.Scalar = literal ? "'" : "\""
        // A newline right after the opening delimiter isn't part of the string.
        if consume("\r") { _ = consume("\n") } else { _ = consume("\n") }
        var result = String.UnicodeScalarView()
        while let scalar = peek() {
            if scalar == delimiter, peek(1) == delimiter, peek(2) == delimiter {
                index += 3
                // Up to two more quotes right before the closing ones belong to the string.
                for _ in 0..<2 where peek() == delimiter {
                    result.append(delimiter)
                    index += 1
                }
                return String(result)
            }
            index += 1
            if scalar == "\n" { line += 1 }
            if !literal, scalar == "\\" {
                // A backslash ending a line trims the newline and the whitespace after it.
                var lookahead = index
                while lookahead < scalars.count, scalars[lookahead] == " " || scalars[lookahead] == "\t" { lookahead += 1 }
                if lookahead < scalars.count, scalars[lookahead] == "\n" || scalars[lookahead] == "\r" {
                    index = lookahead
                    while let space = peek(), " \t\r\n".unicodeScalars.contains(space) {
                        if space == "\n" { line += 1 }
                        index += 1
                    }
                    continue
                }
                result.append(contentsOf: try escape())
                continue
            }
            result.append(scalar)
        }
        throw failure("Unterminated multi-line string.")
    }

    private mutating func escape() throws(TOMLError) -> [Unicode.Scalar] {
        guard let scalar = next() else { throw failure("Unterminated escape.") }
        switch scalar {
        case "b": return ["\u{08}"]
        case "t": return ["\t"]
        case "n": return ["\n"]
        case "f": return ["\u{0C}"]
        case "r": return ["\r"]
        case "e": return ["\u{1B}"]
        case "\"": return ["\""]
        case "\\": return ["\\"]
        case "u", "U":
            let count = scalar == "u" ? 4 : 8
            guard index + count <= scalars.count else { throw failure("Short unicode escape.") }
            let hex = String(String.UnicodeScalarView(scalars[index..<(index + count)]))
            index += count
            guard let code = UInt32(hex, radix: 16), let unicode = Unicode.Scalar(code) else { throw failure("Invalid unicode escape \\\(scalar)\(hex).") }
            return [unicode]
        default:
            throw failure("Invalid escape \\\(scalar).")
        }
    }

    // MARK: - Scanning

    private func peek(_ offset: Int = 0) -> Unicode.Scalar? {
        index + offset < scalars.count ? scalars[index + offset] : nil
    }

    private mutating func next() -> Unicode.Scalar? {
        guard let scalar = peek() else { return nil }
        index += 1
        return scalar
    }

    private mutating func consume(_ scalar: Unicode.Scalar) -> Bool {
        guard peek() == scalar else { return false }
        index += 1
        return true
    }

    private mutating func expect(_ scalar: Unicode.Scalar) throws(TOMLError) {
        skipBlank(newlines: false)
        guard consume(scalar) else { throw failure("Expected \"\(scalar)\".") }
    }

    /// Skips spaces, tabs and comments, and newlines too when `newlines` is set.
    private mutating func skipBlank(newlines: Bool) {
        while let scalar = peek() {
            switch scalar {
            case " ", "\t":
                index += 1
            case "#":
                while let next = peek(), next != "\n" { index += 1 }
            case "\r" where newlines:
                index += 1
            case "\n" where newlines:
                line += 1
                index += 1
            default:
                return
            }
        }
    }

    private func failure(_ message: String) -> TOMLError {
        TOMLError(line: line, message: message)
    }
}
