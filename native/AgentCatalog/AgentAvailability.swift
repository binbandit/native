import ACP
import Foundation

/// Where an agent stands for the user, from "not on this Mac" to "ready". It folds together
/// whether it's installed, whether its plugin is on, how its runtime started and whether it wants a
/// sign-in, so the sidebar footer, composer, menus and settings show one agent the same way.
///
/// Minimal by default: only `isListed` agents appear outside Settings; the rest are offered in Add
/// Agent (not installed) or switched back on in Settings ▸ Agents (disabled).
enum AgentAvailability: Equatable {
    /// Its CLI isn't on the PATH: never started, offered in Add Agent with how to install it.
    case notInstalled(missing: String)
    /// Installed, but the user turned its plugin off.
    case disabled
    case starting
    case ready
    /// Running, but it turns sessions away until the user signs in.
    case needsSignIn
    case signingIn
    /// It launched and stopped, or never got going; the message ends with what it logged.
    case failed(String)

    init(installation: AgentInstallation?, isEnabled: Bool, runtime: AgentRuntime?) {
        if let missing = installation?.missingCommand {
            self = .notInstalled(missing: missing)
        } else if !isEnabled {
            self = .disabled
        } else if let runtime {
            self.init(runtime)
        } else {
            self = .starting
        }
    }

    /// From a running agent's runtime, with signing in folded in.
    init(_ runtime: AgentRuntime) {
        switch runtime.status {
        // An idle agent starts on demand, so to the user it's simply ready; no look of its own.
        case .ready, .idle:
            self = runtime.isSigningIn ? .signingIn : runtime.needsSignIn ? .needsSignIn : .ready
        case .starting: self = .starting
        case .notInstalled(let command): self = .notInstalled(missing: command)
        case .failed(let message): self = .failed(message)
        }
    }

    /// Whether the agent shows in the sidebar, composer and new-session menus.
    var isListed: Bool {
        switch self {
        case .notInstalled, .disabled: false
        case .starting, .ready, .needsSignIn, .signingIn, .failed: true
        }
    }

    /// Whether a new session can start now (a signed-out agent asks for sign-in first).
    var canStartSessions: Bool {
        self == .ready || self == .needsSignIn
    }

    var label: String {
        switch self {
        case .notInstalled: "Not installed"
        case .disabled: "Turned off"
        case .starting: "Starting…"
        case .ready: "Ready"
        case .needsSignIn: "Signed out"
        case .signingIn: "Signing in…"
        case .failed: "Stopped"
        }
    }

    var severity: AgentRuntimeStatus.Severity {
        switch self {
        case .starting, .signingIn: .progress
        case .ready: .ok
        case .notInstalled, .disabled, .needsSignIn: .attention
        case .failed: .problem
        }
    }

    /// What to tell the user beyond the label, using the agent's setup guide where it has one.
    func guidance(for agent: AgentManifest) -> String? {
        switch self {
        case .starting, .ready, .signingIn: nil
        case .notInstalled(let missing):
            if let install = agent.setup?.install {
                "Native couldn't find `\(missing)` on your PATH. Install it with `\(install)`, then choose Check Again."
            } else {
                "Native couldn't find `\(missing)` on your PATH. Install it, then choose Check Again."
            }
        case .disabled: "Turn it on in Settings ▸ Agents to start tasks with \(agent.name)."
        case .needsSignIn:
            if let signIn = agent.setup?.signIn {
                "Sign in to start tasks with \(agent.name), or run `\(signIn)` in a terminal."
            } else {
                "Sign in to start tasks with \(agent.name)."
            }
        case .failed(let message): message
        }
    }
}
