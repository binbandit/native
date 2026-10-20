#if NATIVE_HOSTSUI_WIP
import ACP
import Foundation

/// One way an agent offers to sign in, sorted by what it needs from the machine the agent runs on.
/// That matters on a host nobody sits at: a method that opens a browser opens it there, where no
/// one sees it, while an API key or a device code works from this Mac.
struct HostSignInMethod: Identifiable, Hashable {
    enum Kind: Hashable {
        /// The agent opens a browser on its own machine and waits.
        case browser
        /// The agent takes an API key or token, kept on its machine; `label` names it ("API key").
        case apiKey(label: String?)
        /// The agent shows a page (and often a code) to open in any browser, on any device.
        case link
        /// Only works in a terminal on the agent's machine: `command`.
        case terminal(command: String)
    }

    let method: AuthMethod
    let kind: Kind

    var id: String { method.id }

    /// Whether it signs in from this Mac with nobody at the host: an API key or a device code.
    var worksFromHere: Bool {
        switch kind {
        case .apiKey, .link: true
        case .browser, .terminal: false
        }
    }
}

extension HostSignInMethod {
    /// Sorts `method` by its kind. Nil for a method Native can't offer: a kind this build doesn't
    /// know, or variables it can't fill in with one key.
    init?(_ method: AuthMethod, agent: AgentDefinition) {
        self.method = method
        switch method.kind {
        case .terminal:
            guard let terminal = AgentTerminalSignIn(agent: agent, method: method, startsSession: false) else {
                return nil
            }
            kind = .terminal(command: terminal.command)
        case .apiKey, .environment:
            guard method.takesSecret else { return nil }
            kind = .apiKey(label: method.secretVariable?.label)
        case .link:
            kind = .link
        case .agent:
            // However the agent signs in, it does it where it runs: usually a browser there.
            kind = .browser
        case .unknown:
            return nil
        }
    }
}
#endif
