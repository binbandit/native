import MCPClient
import SwiftUI

/// Where an MCP server stands. Every MCP view shows status through this, so a server reads the
/// same in Settings, the session's list and the status bar.
enum MCPHealth: Hashable {
    /// Not probed yet this launch.
    case unchecked
    case checking
    case connected(tools: Int)
    case needsAuth(MCPAuthChallenge)
    case failed(MCPProbeFailure)
    /// Configured but not loaded: turned off, awaiting approval, or not handed to this agent.
    case inactive(String)

    var label: String {
        switch self {
        case .unchecked: "Not checked"
        case .checking: "Checking…"
        case .connected(let tools): tools == 1 ? "1 tool" : "\(tools) tools"
        case .needsAuth: "Needs sign-in"
        case .failed: "Failed"
        case .inactive(let reason): reason
        }
    }

    var color: Color {
        switch self {
        case .connected: .dsSuccess
        case .needsAuth: .dsWarning
        case .failed: .dsDanger
        case .unchecked, .checking, .inactive: .dsTextTertiary
        }
    }

    var needsAttention: Bool {
        switch self {
        case .needsAuth, .failed: true
        default: false
        }
    }
}

extension ConfiguredServer.Status {
    /// Why the agent doesn't load an entry, for `MCPHealth.inactive`; nil when it does.
    var inactiveReason: String? {
        switch self {
        case .enabled: nil
        case .disabled: "Turned off"
        case .disabledInProject: "Off in this project"
        case .awaitingApproval: "Awaiting approval"
        }
    }
}

extension ManagedServerDelivery.Outcome {
    /// Why a session doesn't get a managed server; nil when it does.
    func inactiveReason(agentName: String) -> String? {
        switch self {
        case .deliver: nil
        case .disabled: "Turned off"
        case .notForAgent: "Not for \(agentName)"
        case .notForProject: "Off in this project"
        case .unsupportedTransport(let kind): "\(agentName) can't use \(kind.displayName)"
        case .alreadyLoaded(let entry): "\(agentName) loads its own (\(entry.scope.displayName.lowercased()))"
        }
    }
}
