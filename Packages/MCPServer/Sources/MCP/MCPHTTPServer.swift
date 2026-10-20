import Foundation
import Network
import Synchronization

/// An MCP server over Streamable HTTP on 127.0.0.1, serving tools at `/mcp/<token>`.
///
/// Every token names a client of the server, resolved to a `Context` the tools receive, so one
/// server can give many clients tools that act on their behalf. Unknown tokens get 404.
///
/// Each connection serves one request and closes, with a plain JSON response. A client that wants
/// several requests in flight opens several connections, so a long tool call never holds up
/// another, and hanging up is how a client cancels one.
public final class MCPHTTPServer<Context: Sendable>: Sendable {
    let endpoint: MCPEndpoint<Context>
    private let maxBodyBytes: Int
    private let queue = DispatchQueue(label: "MCPHTTPServer")
    private let state = Mutex(State())

    private struct State {
        var listener: NWListener?
        var port: UInt16?
        var connections: [ObjectIdentifier: NWConnection] = [:]
    }

    /// - Parameters:
    ///   - instructions: Told to the model alongside the tools: when and how to use them.
    ///   - resolve: The client a token names, or nil for a token that names none.
    public init(
        name: String,
        version: String,
        instructions: String? = nil,
        tools: [MCPTool<Context>],
        maxBodyBytes: Int = 4 * 1024 * 1024,
        resolve: @escaping @Sendable (_ token: String) async -> Context?
    ) {
        endpoint = MCPEndpoint(name: name, version: version, instructions: instructions, tools: tools, resolve: resolve)
        self.maxBodyBytes = maxBodyBytes
    }

    /// Nil until the server has started.
    public var port: UInt16? {
        state.withLock { $0.port }
    }

    /// Where the client named by `token` reaches the server. `token` should be URL-safe.
    public func url(for token: String) -> URL? {
        port.flatMap { URL(string: "http://127.0.0.1:\($0)/mcp/\(token)") }
    }

    /// Listens on `port`, or on one the system picks when it's nil, returning once connections are
    /// accepted. Throws `MCPPortInUse` when `port` is taken.
    public func start(on port: UInt16? = nil) async throws {
        let parameters = NWParameters.tcp
        // Loopback only: nothing off this Mac can reach the server.
        parameters.requiredLocalEndpoint = .hostPort(
            host: .ipv4(.loopback), port: port.flatMap(NWEndpoint.Port.init(rawValue:)) ?? .any)
        let listener = try NWListener(using: parameters)
        let (states, continuation) = AsyncStream.makeStream(of: NWListener.State.self)
        listener.stateUpdateHandler = { continuation.yield($0) }
        listener.newConnectionHandler = { [weak self] connection in self?.accept(connection) }
        listener.start(queue: queue)
        defer { listener.stateUpdateHandler = nil }
        for await state in states {
            switch state {
            case .ready:
                self.state.withLock {
                    $0.listener = listener
                    $0.port = listener.port?.rawValue
                }
                return
            case .failed(let error), .waiting(let error):
                listener.cancel()
                if let port, error == .posix(.EADDRINUSE) {
                    throw MCPPortInUse(port: port)
                }
                throw error
            case .cancelled:
                throw CancellationError()
            default:
                continue
            }
        }
        // The stream only ends early when the starting task is cancelled.
        listener.cancel()
        throw CancellationError()
    }

    /// Stops listening and drops every open connection, cancelling the requests on them.
    public func stop() {
        let (listener, connections) = state.withLock { state in
            defer { state = State() }
            return (state.listener, Array(state.connections.values))
        }
        listener?.cancel()
        connections.forEach { $0.cancel() }
    }

    private func accept(_ connection: NWConnection) {
        state.withLock { $0.connections[ObjectIdentifier(connection)] = connection }
        connection.start(queue: queue)
        Task {
            await serve(connection)
            connection.cancel()
            state.withLock { $0.connections[ObjectIdentifier(connection)] = nil }
        }
    }

    private func serve(_ connection: NWConnection) async {
        // A client that connects and never finishes its request doesn't get to hold on.
        let readDeadline = Task {
            try await Task.sleep(for: .seconds(30))
            connection.cancel()
        }
        defer { readDeadline.cancel() }
        var buffer = Data()
        let request: HTTPRequest
        read: while true {
            let chunk = await connection.receiveChunk()
            buffer.append(chunk.data)
            switch HTTPRequest.parse(buffer, maxBodyBytes: maxBodyBytes) {
            case .complete(let parsed):
                request = parsed
                break read
            case .rejected(let response):
                await connection.send(response)
                return
            case .incomplete:
                if chunk.isComplete { return }
            }
        }
        readDeadline.cancel()

        let response = Task { await endpoint.respond(to: request) }
        // HTTP clients cancel a request by hanging up, so stop working on it when they do.
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1) { _, _, isComplete, error in
            if isComplete || error != nil {
                response.cancel()
            }
        }
        await connection.send(response.value)
    }
}

/// The port a server was asked to listen on is taken.
public struct MCPPortInUse: Error, Hashable, Sendable {
    public var port: UInt16
}
