#if canImport(Network) && canImport(CryptoKit)
import Foundation
import Testing

@testable import MCP

/// A server whose URLs outlive it: the remembered port, the secret behind its tokens, and what
/// happens when the port is taken.
@Suite(.timeLimit(.minutes(1)))
struct RememberedServerTests {
    let folder = FileManager.default.temporaryDirectory.appending(path: "MCPTests-\(UUID().uuidString)")
    let client = UUID()

    /// A server whose tokens name clients by id.
    private func makeServer(_ tokens: MCPTokens) -> MCPHTTPServer<UUID> {
        MCPHTTPServer(name: "test", version: "1.0", tools: []) { tokens.client(in: $0) }
    }

    private func ping(_ url: URL) async throws -> Int {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        let body: JSON = ["jsonrpc": "2.0", "id": 1, "method": "ping"]
        request.httpBody = body.encoded()
        let (_, response) = try await URLSession(configuration: .ephemeral).data(for: request)
        return (response as? HTTPURLResponse)?.statusCode ?? 0
    }

    private func permissions(_ url: URL) throws -> Int {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path(percentEncoded: false))
        return try #require(attributes[.posixPermissions] as? Int)
    }

    @Test func keepsItsSecretReadableByTheUserAlone() throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = MCPServerStore(directory: folder)
        let first = try store.secret()
        #expect(first.isNew)
        let again = try store.secret()
        #expect(!again.isNew)
        #expect(again.secret == first.secret)
        #expect(try permissions(folder) == 0o700)
        #expect(try permissions(folder.appending(path: "token-secret")) == 0o600)
    }

    @Test func replacesASecretOthersCouldRead() throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = MCPServerStore(directory: folder)
        let first = try store.secret().secret
        let file = folder.appending(path: "token-secret").path(percentEncoded: false)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: file)
        let replaced = try store.secret()
        #expect(replaced.isNew)
        #expect(replaced.secret != first)
        #expect(try permissions(folder.appending(path: "token-secret")) == 0o600)
    }

    @Test func reusesTheRememberedPortAndTokens() async throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = MCPServerStore(directory: folder)

        let tokens = MCPTokens()
        let server = makeServer(tokens)
        let first = try await server.start(remembering: store, scope: "dev", tokens: tokens)
        let token = try #require(tokens.token(for: client))
        let url = try #require(server.url(for: token))
        #expect(try await ping(url) == 200)
        server.stop()
        #expect(store.port == first.port)

        // The next launch: the same URL reaches the new server as the same client.
        let nextTokens = MCPTokens()
        let next = makeServer(nextTokens)
        let launch = try await next.start(remembering: store, scope: "dev", tokens: nextTokens)
        defer { next.stop() }
        #expect(launch == MCPServerLaunch(port: first.port, movedFrom: nil, storeFailure: nil))
        #expect(nextTokens.token(for: client) == token)
        #expect(try await ping(url) == 200)
    }

    @Test func movesWhenThePortIsTakenAndRetiresTheOldTokens() async throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = MCPServerStore(directory: folder)
        let tokens = MCPTokens()
        let server = makeServer(tokens)
        let first = try await server.start(remembering: store, scope: "dev", tokens: tokens)
        // Still listening, so the port is taken.
        defer { server.stop() }
        let oldToken = try #require(tokens.token(for: client))

        let nextTokens = MCPTokens()
        let next = makeServer(nextTokens)
        let launch = try await next.start(remembering: store, scope: "dev", tokens: nextTokens, patience: .zero)
        defer { next.stop() }
        #expect(launch.port != first.port)
        #expect(launch.movedFrom == first.port)
        #expect(store.port == launch.port)

        // Whoever holds the old port may have seen the old tokens: they don't work here.
        let newToken = try #require(nextTokens.token(for: client))
        #expect(newToken != oldToken)
        #expect(try await ping(try #require(next.url(for: oldToken))) == 404)
        #expect(try await ping(try #require(next.url(for: newToken))) == 200)
    }

    @Test func refusesTokensItDidNotSign() async throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let tokens = MCPTokens()
        let server = makeServer(tokens)
        _ = try await server.start(remembering: MCPServerStore(directory: folder), scope: "dev", tokens: tokens)
        defer { server.stop() }
        let token = try #require(tokens.token(for: client))
        let flipped = String(token.dropLast()) + (token.hasSuffix("0") ? "1" : "0")
        let otherChannel = MCPTokenSigner(secret: MCPTokenSigner.newSecret(), scope: "nightly").token(for: client)

        for wrong in [flipped, otherChannel, client.uuidString.lowercased()] {
            #expect(try await ping(try #require(server.url(for: wrong))) == 404)
        }
        #expect(try await ping(try #require(server.url(for: token))) == 200)
    }

    @Test func aTakenPortIsReported() async throws {
        let server = makeServer(MCPTokens())
        try await server.start()
        defer { server.stop() }
        let port = try #require(server.port)
        await #expect(throws: MCPPortInUse(port: port)) {
            try await makeServer(MCPTokens()).start(on: port)
        }
    }
}
#endif
