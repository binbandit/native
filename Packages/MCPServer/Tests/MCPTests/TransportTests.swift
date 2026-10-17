import Foundation
import Testing
@testable import MCP

/// The server over real loopback connections.
@Suite(.timeLimit(.minutes(1)))
struct TransportTests {
    private func call(_ url: URL, _ body: JSON, session: URLSession = .shared) async throws -> (JSON?, Int) {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body.encoded()
        let (data, response) = try await session.data(for: request)
        return (try? JSONDecoder().decode(JSON.self, from: data), (response as? HTTPURLResponse)?.statusCode ?? 0)
    }

    @Test func servesRequestsOnLoopback() async throws {
        let server = makeServer()
        try await server.start()
        defer { server.stop() }
        let url = try #require(server.url(for: "alice"))
        #expect(url.host() == "127.0.0.1")

        let (json, status) = try await call(url, ["jsonrpc": "2.0", "id": 1, "method": "tools/call", "params": ["name": "echo", "arguments": ["text": "hi"]]])
        #expect(status == 200)
        #expect(json?["result"]?["structuredContent"]?["text"] == "hi")

        let (_, missing) = try await call(try #require(server.url(for: "mallory")), ["jsonrpc": "2.0", "id": 1, "method": "ping"])
        #expect(missing == 404)
    }

    @Test func aSlowCallHoldsUpNothingElseAndHangingUpCancelsIt() async throws {
        let (events, continuation) = AsyncStream.makeStream(of: String.self)
        var iterator = events.makeAsyncIterator()
        let server = makeServer(events: continuation)
        try await server.start()
        defer { server.stop() }
        let url = try #require(server.url(for: "alice"))

        let session = URLSession(configuration: .ephemeral)
        let slow = Task { try await call(url, ["jsonrpc": "2.0", "id": 1, "method": "tools/call", "params": ["name": "slow"]], session: session) }
        #expect(await iterator.next() == "started")

        let (ping, status) = try await call(url, ["jsonrpc": "2.0", "id": 2, "method": "ping"])
        #expect(status == 200)
        #expect(ping?["id"] == 2)

        slow.cancel()
        #expect(await iterator.next() == "cancelled")
    }

    @Test func stopRefusesNewConnections() async throws {
        let server = makeServer()
        try await server.start()
        let url = try #require(server.url(for: "alice"))
        server.stop()
        #expect(server.port == nil)
        await #expect(throws: URLError.self) {
            try await call(url, ["jsonrpc": "2.0", "id": 1, "method": "ping"])
        }
    }
}
