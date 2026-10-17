import Foundation
import Network
import Synchronization

/// A loopback HTTP server answering each request with whatever the test's handler returns, for
/// replies a real MCP server wouldn't give on demand (401s, event streams).
final class StubHTTPServer: Sendable {
    struct Request: Sendable {
        var method: String
        var path: String
        /// Lowercased names.
        var headers: [String: String]
        var body: String
    }

    struct Response: Sendable {
        var status: Int
        var headers: [String: String] = [:]
        var body = ""
    }

    private let listener: NWListener
    private let handler: @Sendable (Request) -> Response
    private let received = Mutex<[Request]>([])
    let port: UInt16

    init(handler: @escaping @Sendable (Request) -> Response) async throws {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: .any)
        let listener = try NWListener(using: parameters)
        self.listener = listener
        self.handler = handler
        let (states, continuation) = AsyncStream.makeStream(of: NWListener.State.self)
        listener.stateUpdateHandler = { continuation.yield($0) }
        let box = Mutex<StubHTTPServer?>(nil)
        listener.newConnectionHandler = { connection in box.withLock { $0 }?.serve(connection) }
        listener.start(queue: .global())
        var port: UInt16 = 0
        for await state in states {
            if case .ready = state {
                port = listener.port?.rawValue ?? 0
                break
            }
            if case .failed(let error) = state { throw error }
        }
        self.port = port
        box.withLock { $0 = self }
    }

    var url: URL {
        URL(string: "http://127.0.0.1:\(port)/mcp")!
    }

    var requests: [Request] {
        received.withLock { $0 }
    }

    func stop() {
        listener.cancel()
    }

    private func serve(_ connection: NWConnection) {
        connection.start(queue: .global())
        read(connection, buffer: Data())
    }

    private func read(_ connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [self] data, _, isComplete, error in
            var buffer = buffer
            if let data { buffer.append(data) }
            if let request = Self.parse(buffer) {
                received.withLock { $0.append(request) }
                let response = handler(request)
                var head = "HTTP/1.1 \(response.status) Stub\r\nContent-Length: \(response.body.utf8.count)\r\nConnection: close\r\n"
                for (name, value) in response.headers { head += "\(name): \(value)\r\n" }
                connection.send(content: Data((head + "\r\n" + response.body).utf8), completion: .contentProcessed { _ in connection.cancel() })
            } else if isComplete || error != nil {
                connection.cancel()
            } else {
                read(connection, buffer: buffer)
            }
        }
    }

    private static func parse(_ data: Data) -> Request? {
        guard let separator = data.firstRange(of: Data("\r\n\r\n".utf8)) else { return nil }
        let head = String(decoding: data[..<separator.lowerBound], as: UTF8.self).components(separatedBy: "\r\n")
        let start = head.first?.split(separator: " ") ?? []
        var headers: [String: String] = [:]
        for line in head.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { continue }
            headers[line[..<colon].lowercased()] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }
        let body = data[separator.upperBound...]
        guard body.count >= Int(headers["content-length"] ?? "0") ?? 0 else { return nil }
        return Request(method: start.first.map(String.init) ?? "", path: start.dropFirst().first.map(String.init) ?? "", headers: headers, body: String(decoding: body, as: UTF8.self))
    }
}
