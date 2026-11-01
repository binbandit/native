import Foundation
import MCP

/// The CLI uses the same tool names and arguments as MCP, without loading their schemas into context.
public struct NativeActionCommand: Sendable {
    public static let usage = "native <tool> [JSON arguments | --stdin] [--text]"
    public static let tools: Set<String> = [
        "list_agents", "start_task", "list_tasks", "wait_for_task", "get_task", "send_message",
        "cancel_task", "list_skills", "get_skill", "setup_status", "run_script",
    ]

    public let tool: String
    public let arguments: JSON
    public let text: Bool

    public init(_ given: [String], input: () throws -> Data = { FileHandle.standardInput.readDataToEndOfFile() }) throws
    {
        var given = given
        text = given.last == "--text"
        if text { given.removeLast() }
        guard (1...2).contains(given.count), let name = given.first, Self.tools.contains(name) else {
            throw Failure.usage
        }
        tool = name
        let data = try given.count == 1 ? Data("{}".utf8) : given[1] == "--stdin" ? input() : Data(given[1].utf8)
        guard data.count <= 4 * 1024 * 1024,
            let json = try? JSONDecoder().decode(JSON.self, from: data), json.objectValue != nil
        else { throw Failure.arguments }
        arguments = json
    }

    /// No arbitrary destinations, credentials in query strings, redirects, or global fallback session.
    public static func endpoint(_ value: String) throws -> URL {
        guard let url = URL(string: value), let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
            parts.scheme == "http", parts.host == "127.0.0.1", let port = parts.port, (1...65535).contains(port),
            parts.user == nil, parts.password == nil, parts.query == nil, parts.fragment == nil,
            url.pathComponents.count == 3, url.pathComponents[1] == "mcp", !url.lastPathComponent.isEmpty
        else { throw Failure.session }
        return url
    }

    public enum Failure: Error, LocalizedError {
        case usage, arguments, session, unavailable, denied, response(String)

        public var errorDescription: String? {
            switch self {
            case .usage: NativeActionCommand.usage
            case .arguments: "Arguments must be a JSON object no larger than 4 MiB."
            case .session: "No Native session credential. Run this command in a Native task."
            case .unavailable: "Native's local tools are unavailable. Reopen the task in Native and try again."
            case .denied: "Native refused this session or your organization's policy does not allow its tools."
            case .response(let message): message
            }
        }
    }
}
