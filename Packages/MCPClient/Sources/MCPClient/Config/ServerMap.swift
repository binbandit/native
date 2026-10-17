import Foundation
import MCP

/// The `"mcpServers": { "<name>": { … } }` shape Claude Code and Cursor share: `command`, `args`,
/// `env` (and `cwd`) for local servers, `url` and `headers` for remote ones, and an optional
/// `type`.
enum ServerMap {
    /// The servers in `map`, sorted by name. Entries Native can't connect to (WebSocket, in-process
    /// SDK servers) become problems instead.
    static func servers(in map: JSON?, file: URL, problems: inout [ConfigProblem]) -> [MCPServerConfig] {
        guard let entries = map?.objectValue else { return [] }
        return entries.keys.sorted().compactMap { name -> MCPServerConfig? in
            guard let entry = entries[name]?.objectValue else {
                problems.append(ConfigProblem(file: file, message: "\"\(name)\" isn't an object."))
                return nil
            }
            do throws(Unsupported) {
                return try server(named: name, entry)
            } catch {
                problems.append(ConfigProblem(file: file, message: "\"\(name)\": \(error.message)"))
                return nil
            }
        }
    }

    struct Unsupported: Error {
        let message: String
    }

    static func server(named name: String, _ entry: [String: JSON]) throws(Unsupported) -> MCPServerConfig {
        let type = entry["type"]?.stringValue?.lowercased()
        if let command = entry["command"]?.stringValue, type == nil || type == "stdio" {
            return MCPServerConfig(name: name, transport: .stdio(
                command: command,
                arguments: strings(entry["args"]),
                environment: dictionary(entry["env"]),
                workingDirectory: entry["cwd"]?.stringValue
            ))
        }
        if let text = entry["url"]?.stringValue ?? entry["serverUrl"]?.stringValue {
            guard let url = URL(string: text) else { throw Unsupported(message: "the URL \"\(text)\" isn't valid.") }
            let headers = dictionary(entry["headers"])
            switch type {
            case nil, "http", "streamable-http", "streamable_http", "streamablehttp": return MCPServerConfig(name: name, transport: .http(url: url, headers: headers))
            case "sse": return MCPServerConfig(name: name, transport: .sse(url: url, headers: headers))
            case let type?: throw Unsupported(message: "the \(type) transport isn't supported.")
            }
        }
        throw Unsupported(message: type.map { "the \($0) transport isn't supported." } ?? "it has neither a command nor a URL.")
    }

    static func strings(_ value: JSON?) -> [String] {
        guard case .array(let items) = value else { return [] }
        return items.compactMap(\.scalarText)
    }

    static func dictionary(_ value: JSON?) -> [String: String] {
        (value?.objectValue ?? [:]).compactMapValues(\.scalarText)
    }
}

extension JSON {
    /// Strings as they are; numbers and booleans as configuration files mean them.
    var scalarText: String? {
        switch self {
        case .string(let string): string
        case .number(let number): number.rounded() == number && abs(number) < 1e15 ? String(Int64(number)) : String(number)
        case .bool(let bool): String(bool)
        case .null, .array, .object: nil
        }
    }

    var boolValue: Bool? {
        guard case .bool(let bool) = self else { return nil }
        return bool
    }

    var arrayValue: [JSON]? {
        guard case .array(let array) = self else { return nil }
        return array
    }

    var stringArray: [String] {
        arrayValue?.compactMap(\.stringValue) ?? []
    }
}

/// Reads a JSON file into `JSON`, reporting a problem only when the file exists but can't be read.
enum ConfigFileReader {
    static func json(at url: URL, problems: inout [ConfigProblem]) -> JSON? {
        guard let data = FileManager.default.contents(atPath: url.path(percentEncoded: false)) else { return nil }
        do {
            return try JSONDecoder().decode(JSON.self, from: data)
        } catch {
            problems.append(ConfigProblem(file: url, message: "It isn't valid JSON."))
            return nil
        }
    }

    static func exists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path(percentEncoded: false))
    }
}
