import Foundation
import MCP
import Synchronization

/// A remote server over Streamable HTTP: each message is a POST, answered with JSON or with an
/// event stream carrying the reply. The session id and protocol version the server hands out on
/// `initialize` go on every later request.
final class StreamableHTTPTransport: MCPClientTransport {
    private let url: URL
    private let headers: [String: String]
    private let session: URLSession
    private let state = Mutex(State())

    private struct State {
        var sessionID: String?
        var protocolVersion: String?
    }

    init(url: URL, headers: [String: String], session: URLSession) {
        self.url = url
        self.headers = headers
        self.session = session
    }

    func request(_ method: String, params: JSON, id: Int) async throws(ProbeError) -> JSON {
        let (bytes, response) = try await post(JSONRPC.request(method, params: params, id: id), stage: method == "initialize" ? .connect : .listTools)
        if method == "initialize", [404, 405].contains(response.statusCode) {
            throw .notStreamableHTTP(status: response.statusCode)
        }
        try await check(response, bytes: bytes, sentCredentials: sendsCredentials)
        if let sessionID = response.value(forHTTPHeaderField: "Mcp-Session-Id") {
            state.withLock { $0.sessionID = sessionID }
        }
        let result: Result<JSON, JSONRPC.RPCFailure>
        if response.value(forHTTPHeaderField: "Content-Type")?.lowercased().contains("text/event-stream") == true {
            result = try await Self.reply(to: id, inEventStream: bytes)
        } else {
            let body = try await Self.collect(bytes)
            guard case .response(id, let reply)? = JSONRPC.decode(body) else {
                throw .failure(.initialize, "The server's reply isn't JSON-RPC: \(Self.excerpt(body))")
            }
            result = reply
        }
        let value = try result.mapError { ProbeError.failure(.initialize, "The server answered with an error: \($0.message) (\($0.code)).") }.get()
        if method == "initialize", let version = value["protocolVersion"]?.stringValue {
            state.withLock { $0.protocolVersion = version }
        }
        return value
    }

    func notify(_ method: String, params: JSON) async throws(ProbeError) {
        let (bytes, response) = try await post(JSONRPC.notification(method, params: params), stage: .initialize)
        try await check(response, bytes: bytes, sentCredentials: sendsCredentials)
    }

    /// Ends the server's session, if it gave one, so it doesn't linger.
    func close() async {
        guard let sessionID = state.withLock({ $0.sessionID }) else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue(sessionID, forHTTPHeaderField: "Mcp-Session-Id")
        headers.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
        _ = try? await session.data(for: request)
    }

    private var sendsCredentials: Bool {
        headers.keys.contains { $0.caseInsensitiveCompare("Authorization") == .orderedSame }
    }

    private func post(_ body: Data, stage: MCPProbeFailure.Stage) async throws(ProbeError) -> (URLSession.AsyncBytes, HTTPURLResponse) {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = body
        headers.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json, text/event-stream", forHTTPHeaderField: "Accept")
        let (sessionID, version) = state.withLock { ($0.sessionID, $0.protocolVersion) }
        request.setValue(sessionID, forHTTPHeaderField: "Mcp-Session-Id")
        request.setValue(version, forHTTPHeaderField: "MCP-Protocol-Version")
        return try await Self.send(request, on: session, stage: stage)
    }

    static func send(_ request: URLRequest, on session: URLSession, stage: MCPProbeFailure.Stage) async throws(ProbeError) -> (URLSession.AsyncBytes, HTTPURLResponse) {
        do {
            let (bytes, response) = try await session.bytes(for: request)
            guard let http = response as? HTTPURLResponse else { throw ProbeError.failure(stage, "The server's reply isn't HTTP.") }
            return (bytes, http)
        } catch let error as ProbeError {
            throw error
        } catch is CancellationError {
            throw .cancelled
        } catch {
            throw .failure(stage, "Couldn't reach \(request.url?.host() ?? "the server"): \(error.localizedDescription)")
        }
    }

    /// Turns away anything but success: 401 and 403 as a sign-in the probe can't do, the rest with
    /// the start of the server's explanation.
    func check(_ response: HTTPURLResponse, bytes: URLSession.AsyncBytes, sentCredentials: Bool) async throws(ProbeError) {
        try await Self.check(response, bytes: bytes, sentCredentials: sentCredentials)
    }

    static func check(_ response: HTTPURLResponse, bytes: URLSession.AsyncBytes, sentCredentials: Bool) async throws(ProbeError) {
        switch response.statusCode {
        case 200..<300:
            return
        case 401, 403:
            throw .needsAuth(MCPAuthChallenge(
                statusCode: response.statusCode,
                resourceMetadata: MCPAuthChallenge.resourceMetadata(in: response.value(forHTTPHeaderField: "WWW-Authenticate")),
                sentCredentials: sentCredentials
            ))
        default:
            let body = (try? await collect(bytes, limit: 2_048)) ?? Data()
            let detail = excerpt(body)
            throw .failure(.connect, "The server answered HTTP \(response.statusCode)" + (detail.isEmpty ? "." : ": \(detail)"))
        }
    }

    /// Reads events until the one carrying the reply to `id`; the server's own requests and
    /// notifications on the way are skipped.
    static func reply(to id: Int, inEventStream bytes: URLSession.AsyncBytes) async throws(ProbeError) -> Result<JSON, JSONRPC.RPCFailure> {
        var parser = ServerSentEvents()
        do {
            for try await line in LineSequence(bytes: bytes) {
                guard let event = parser.feed(line), case .response(id, let result)? = JSONRPC.decode(Data(event.data.utf8)) else { continue }
                return result
            }
        } catch {
            throw .failure(.initialize, "The server's event stream broke off: \(error.localizedDescription)")
        }
        throw .failure(.initialize, "The server's event stream ended without a reply.")
    }

    static func collect(_ bytes: URLSession.AsyncBytes, limit: Int = 64 * 1024 * 1024) async throws(ProbeError) -> Data {
        var data = Data()
        do {
            for try await byte in bytes {
                data.append(byte)
                if data.count >= limit { break }
            }
        } catch {
            throw .failure(.initialize, "The server's reply broke off: \(error.localizedDescription)")
        }
        return data
    }

    static func excerpt(_ data: Data) -> String {
        let text = String(decoding: data.prefix(300), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return text.count < data.count ? text + "…" : text
    }
}

/// A remote server over the HTTP+SSE transport (protocol 2024-11-05): one long GET stream that
/// first names the endpoint to POST messages to, then carries every reply.
final class LegacySSETransport: MCPClientTransport {
    private let session: URLSession
    private let headers: [String: String]
    private let endpoint: URL
    private let reader: Task<Void, Never>
    private let replies: PendingReplies

    /// Opens the stream and waits for the `endpoint` event.
    static func connect(url: URL, headers: [String: String], session: URLSession) async throws(ProbeError) -> LegacySSETransport {
        var request = URLRequest(url: url)
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        headers.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
        let (bytes, response) = try await StreamableHTTPTransport.send(request, on: session, stage: .connect)
        let sendsCredentials = headers.keys.contains { $0.caseInsensitiveCompare("Authorization") == .orderedSame }
        try await StreamableHTTPTransport.check(response, bytes: bytes, sentCredentials: sendsCredentials)
        let replies = PendingReplies()
        let (endpoints, found) = AsyncStream.makeStream(of: URL.self)
        let reader = Task {
            var parser = ServerSentEvents()
            do {
                for try await line in LineSequence(bytes: bytes) {
                    guard let event = parser.feed(line) else { continue }
                    if event.name == "endpoint" {
                        if let endpoint = URL(string: event.data.trimmingCharacters(in: .whitespacesAndNewlines), relativeTo: url) {
                            found.yield(endpoint.absoluteURL)
                        }
                    } else if case .response(let id, let result)? = JSONRPC.decode(Data(event.data.utf8)) {
                        replies.resolve(id, with: result.mapError { .failure(.initialize, "The server answered with an error: \($0.message) (\($0.code)).") })
                    }
                }
            } catch {}
            found.finish()
            replies.closeAll(with: .failure(.initialize, "The server closed its event stream."))
        }
        var iterator = endpoints.makeAsyncIterator()
        guard let endpoint = await iterator.next() else {
            reader.cancel()
            throw .failure(.connect, "The server's event stream never named an endpoint to send messages to.")
        }
        return LegacySSETransport(session: session, headers: headers, endpoint: endpoint, reader: reader, replies: replies)
    }

    private init(session: URLSession, headers: [String: String], endpoint: URL, reader: Task<Void, Never>, replies: PendingReplies) {
        self.session = session
        self.headers = headers
        self.endpoint = endpoint
        self.reader = reader
        self.replies = replies
    }

    func request(_ method: String, params: JSON, id: Int) async throws(ProbeError) -> JSON {
        let result = await withCheckedContinuation { (continuation: CheckedContinuation<Result<JSON, ProbeError>, Never>) in
            guard replies.await(id, continuation, ifClosed: .failure(.initialize, "The server closed its event stream.")) else { return }
            Task {
                do throws(ProbeError) {
                    try await post(JSONRPC.request(method, params: params, id: id))
                } catch {
                    replies.resolve(id, with: .failure(error))
                }
            }
        }
        return try result.get()
    }

    func notify(_ method: String, params: JSON) async throws(ProbeError) {
        try await post(JSONRPC.notification(method, params: params))
    }

    func close() async {
        reader.cancel()
    }

    private func post(_ body: Data) async throws(ProbeError) {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.httpBody = body
        headers.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let (bytes, response) = try await StreamableHTTPTransport.send(request, on: session, stage: .initialize)
        try await StreamableHTTPTransport.check(response, bytes: bytes, sentCredentials: false)
    }
}

/// Requests waiting for replies that arrive on another channel, by id.
final class PendingReplies: Sendable {
    private struct State {
        var waiting: [Int: CheckedContinuation<Result<JSON, ProbeError>, Never>] = [:]
        var isClosed = false
    }

    private let state = Mutex(State())

    /// Registers `continuation` for `id`; when already closed, resumes it with `closedError` and
    /// returns false.
    func await(_ id: Int, _ continuation: CheckedContinuation<Result<JSON, ProbeError>, Never>, ifClosed closedError: ProbeError) -> Bool {
        let isClosed = state.withLock { state in
            if !state.isClosed { state.waiting[id] = continuation }
            return state.isClosed
        }
        if isClosed { continuation.resume(returning: .failure(closedError)) }
        return !isClosed
    }

    func resolve(_ id: Int, with result: Result<JSON, ProbeError>) {
        state.withLock { $0.waiting.removeValue(forKey: id) }?.resume(returning: result)
    }

    func closeAll(with error: ProbeError) {
        let waiting = state.withLock { state in
            state.isClosed = true
            defer { state.waiting = [:] }
            return Array(state.waiting.values)
        }
        waiting.forEach { $0.resume(returning: .failure(error)) }
    }
}
