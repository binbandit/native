import Foundation

/// How a server came up in `start(remembering:scope:tokens:)`.
public struct MCPServerLaunch: Hashable, Sendable {
    public var port: UInt16
    /// The port it listened on last time, when that one was taken and it had to move. URLs handed
    /// out before this launch point there, so they no longer reach it.
    public var movedFrom: UInt16?
    /// Why the store couldn't be used, when it couldn't: tokens then last only until the server
    /// stops, and the port isn't remembered.
    public var storeFailure: String?
}

extension MCPHTTPServer {
    /// Listens on the port `store` remembers, with tokens signed by its secret, so URLs handed out
    /// in earlier launches keep working; or, when that port is taken, on a port the system picks.
    ///
    /// Moving retires the secret. Clients still holding the old URLs send their tokens to whoever
    /// holds the old port now, so those tokens must never work again, wherever this server listens
    /// later. The new signer is in `tokens` before the server listens anywhere.
    public func start(
        remembering store: MCPServerStore, scope: String, tokens: MCPTokens
    ) async throws -> MCPServerLaunch {
        var failure: String?
        let secret: Data
        do {
            secret = try store.secret().secret
        } catch {
            failure = error.localizedDescription
            secret = MCPTokenSigner.newSecret()
        }
        let remembered = failure == nil ? store.port : nil
        tokens.install(MCPTokenSigner(secret: secret, scope: scope))

        var movedFrom: UInt16?
        do {
            try await start(on: remembered)
        } catch let taken as MCPPortInUse {
            movedFrom = taken.port
            do {
                tokens.install(MCPTokenSigner(secret: try store.replaceSecret(), scope: scope))
            } catch {
                // The old secret mustn't come back next launch either.
                store.forgetSecret()
                failure = error.localizedDescription
                tokens.install(MCPTokenSigner(secret: MCPTokenSigner.newSecret(), scope: scope))
            }
            try await start()
        }

        guard let port else { throw CancellationError() }
        if failure == nil, port != remembered {
            do {
                try store.savePort(port)
            } catch {
                failure = error.localizedDescription
            }
        }
        return MCPServerLaunch(port: port, movedFrom: movedFrom, storeFailure: failure)
    }
}
