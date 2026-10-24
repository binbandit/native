import Foundation

/// Shared sign-in state reported by the credential owner, never inferred from an anonymous probe.
public enum MCPAuthenticationStatus: Hashable, Sendable {
    case signedIn
    case signedOut
    /// The owner hasn't reported its state. Native never reads another app's secrets.
    case unknown
}
