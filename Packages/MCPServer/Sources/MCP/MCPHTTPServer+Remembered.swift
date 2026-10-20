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
    /// in earlier launches keep working; or, when that port stays taken for `patience`, on a port
    /// the system picks. The wait covers the copy of the app this one replaces, which may still be
    /// quitting (a relaunch opens the new copy first).
    ///
    /// Moving retires the secret. Clients still holding the old URLs send their tokens to whoever
    /// holds the old port now, so those tokens must never work again, wherever this server listens
    /// later. The new signer is in `tokens` before the server listens anywhere.
    public func start(
        remembering store: MCPServerStore, scope: String, tokens: MCPTokens, patience: Duration = .seconds(5)
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
            try await listen(on: remembered, patience: patience)
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

    private func listen(on port: UInt16?, patience: Duration) async throws {
        let deadline = ContinuousClock.now.advanced(by: patience)
        while true {
            do {
                return try await start(on: port)
            } catch is MCPPortInUse where ContinuousClock.now < deadline {
                try await Task.sleep(for: .milliseconds(250))
            }
        }
    }
}
