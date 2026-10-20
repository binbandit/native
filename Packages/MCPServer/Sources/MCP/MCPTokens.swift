import Foundation
import Synchronization

/// The tokens a server accepts right now, shared by whoever hands out its URLs and its `resolve`.
/// Empty until `MCPHTTPServer.start(remembering:scope:tokens:)` installs the signer, which it does
/// before the server listens, so no request is ever checked against a secret it's about to retire.
public final class MCPTokens: Sendable {
    private let signer = Mutex<MCPTokenSigner?>(nil)

    public init() {}

    /// The token for `client`, or nil before the server has started.
    public func token(for client: UUID) -> String? {
        signer.withLock { $0?.token(for: client) }
    }

    /// The client a token names, or nil unless the server's current secret signed it.
    public func client(in token: some StringProtocol) -> UUID? {
        signer.withLock { $0?.client(in: token) }
    }

    func install(_ signer: MCPTokenSigner) {
        self.signer.withLock { $0 = signer }
    }
}
