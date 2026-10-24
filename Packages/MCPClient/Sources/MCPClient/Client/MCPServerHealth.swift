import Foundation

/// Combines Native's connection check with the agent's shared sign-in state. An anonymous 401
/// says nothing about credentials held by another client.
public enum MCPServerHealth: Hashable, Sendable {
    case unchecked
    case checking
    case connected(tools: Int)
    case signedIn
    case authenticationUnknown
    case needsAuth(MCPAuthChallenge)
    case failed(MCPProbeFailure)
    case inactive(String)

    public init(
        report: MCPProbeReport?, authentication: MCPAuthenticationStatus? = nil,
        isChecking: Bool = false, inactiveReason: String? = nil
    ) {
        if isChecking {
            self = .checking
        } else if let inactiveReason {
            self = .inactive(inactiveReason)
        } else if let report {
            switch report.status {
            case .connected: self = .connected(tools: report.tools.count)
            case .failed(let failure): self = .failed(failure)
            case .needsAuth(let challenge):
                if challenge.sentCredentials {
                    self = .needsAuth(challenge)
                } else {
                    switch authentication {
                    case .signedIn?: self = .signedIn
                    case .unknown?: self = .authenticationUnknown
                    case .signedOut?, nil: self = .needsAuth(challenge)
                    }
                }
            }
        } else {
            self = authentication == .signedIn ? .signedIn : .unchecked
        }
    }
}
