import Foundation

/// Shared sign-in state reported by the credential owner, never inferred from an anonymous probe.
public enum MCPAuthenticationStatus: Hashable, Sendable {
    case signedIn
    case signedOut
    /// The owner doesn't expose its state, or its credential store couldn't be read.
    case unknown
}
