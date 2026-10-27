import Foundation
import MCP

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// One ordinary tool call to Native's existing authenticated loopback endpoint. No discovery round trip.
public enum NativeActionClient {
    public static func call(_ command: NativeActionCommand, endpoint value: String) async throws -> String {
        let endpoint = try NativeActionCommand.endpoint(value)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 280
        configuration.timeoutIntervalForResource = 285
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        configuration.connectionProxyDictionary = [:]
        let session = URLSession(configuration: configuration, delegate: NoRedirects(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json, text/event-stream", forHTTPHeaderField: "Accept")
        request.setValue("2025-11-25", forHTTPHeaderField: "MCP-Protocol-Version")
        let body: JSON = [
            "jsonrpc": "2.0", "id": 1, "method": "tools/call",
            "params": ["name": .string(command.tool), "arguments": command.arguments],
        ]
        request.httpBody = try JSONEncoder().encode(body)
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            // URLSession errors can include the URL, which carries the session's credential.
            throw NativeActionCommand.Failure.unavailable
        }
        guard let http = response as? HTTPURLResponse else { throw NativeActionCommand.Failure.unavailable }
        guard http.statusCode != 404 && http.statusCode != 403 else { throw NativeActionCommand.Failure.denied }
        guard http.statusCode == 200, let envelope = try? JSONDecoder().decode(JSON.self, from: data) else {
            throw NativeActionCommand.Failure.unavailable
        }
        if let message = envelope["error"]?["message"]?.stringValue {
            throw NativeActionCommand.Failure.response(message)
        }
        guard let result = envelope["result"] else { throw NativeActionCommand.Failure.unavailable }
        let content: [JSON]
        if case .array(let items) = result["content"] { content = items } else { content = [] }
        let message = content.compactMap { $0["text"]?.stringValue }.joined(separator: "\n")
        if result["isError"] == .bool(true) { throw NativeActionCommand.Failure.response(message) }
        if command.text { return message }
        return String(
            decoding: try JSONEncoder().encode(result["structuredContent"] ?? .string(message)), as: UTF8.self)
    }
}

private final class NoRedirects: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(
        _ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}
